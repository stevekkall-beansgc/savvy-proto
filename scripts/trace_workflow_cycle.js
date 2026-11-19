'use strict';

const traceCycle = (() => {
  const stages = {
    source: ['Source delivery', ['source'], 'Provider record ID, source revision and receipt timestamp.'],
    normalized: ['Normalized facts', ['normalized'], 'Fact IDs, source references and normalization run or mapping version.'],
    policy: ['Terms and rate assignment', ['policy'], 'Approved terms or CLM reference, scoped policy version, product and effective dates.'],
    calculation: ['Fee calculation', ['calculation'], 'Result IDs, exact input manifest, assignment ID, currency and service period.'],
    aggregate: ['Billing rollup', ['aggregate'], 'Measure definition, grain, dates, amount basis and contributor IDs or query manifest.'],
    invoice: ['Savvy invoice', ['invoice'], 'Document and line IDs, exact result references, original and revised amounts.'],
    payable: ['Earnings and payable', ['payable'], 'Payable ID, earned amount, earning period and entitlement or result references.'],
    statement: ['Client statement', ['statement'], 'Published statement and line IDs, service dates and linked invoice or earning references.'],
    adjustment: ['Credit or debit memo', ['credit_memo', 'debit_memo'], 'Original invoice and line, authorized reason, amount and application status.'],
    payment: ['Cash and application', ['payment'], 'Cash confirmation, application ID and amount, invoice reference and effective date.'],
    payout: ['Payout and settlement', ['payout'], 'Request, eligible payable, cash confirmation, destination and settlement date.'],
    journal: ['Campfire accounting', ['journal'], 'Posting reference, period, source document and recognition schedule if applicable.'],
    event: ['Billing event or approval', ['event'], 'Event ID and revision, source or approval, effective date and any original-event reference.'],
    package: ['Accounting package', ['accounting_package'], 'Scoped document and line references, package version, treatment and posting period.'],
    reporting: ['Internal report or review', ['report'], 'Report or job name, query or extract version, and reference to the aggregated total.'],
    unmapped: ['Unclassified record', ['unmapped'], 'Confirm the object type and which process creates it.'],
  };

  function rollupContributor(entry) {
    if (entry.type !== 'aggregate' || entry.state === 'reference only') return null;
    const fields = {...entry.preview?.fields, ...entry.evidence};
    const normalized = value => String(value || '').toLowerCase().replace(/[-_]/g, ' ').trim();
    const measure = normalized(fields.measure), basis = normalized(fields.basis);
    if (/\b(?:bank|cash|settlement|payments?|collected|journal|ledger)\b/.test(measure + ' ' + basis)) return null;
    if (!/\binvoic(?:e|es|ed|ing)\b/.test(measure) && basis !== 'issued originals') return null;
    const members = entry.preview?.sections?.members;
    const oneInvoice = fields.contributor_count === '1' && measure === 'original invoice total' &&
      basis === 'issued originals' && (!members || members.total === 0 ||
        (members.total === 1 && members.rows[0]?.kind === 'invoice'));
    const amount = oneInvoice && /^-?\d{1,20}(?:\.\d{1,12})?$/.test(fields.total_amount) ? fields.total_amount : null;
    const currency = /^[A-Z]{3}$/.test(fields.currency) ? fields.currency : null;
    const grain = fields.grain || null;
    const start = fields.period_start || null, end = fields.period_end || null;
    if (![amount, currency, grain, start, end].some(Boolean)) return null;
    return {
      amount, currency, grain, start, end,
      source: entry.id || entry.label,
    };
  }

  function identityFieldsFor(entry) {
    const evidence = entry.evidence;
    const identityFields = [];
    if (!entry.id) identityFields.push('Record ID · unknown');
    if (entry.type === 'aggregate') {
      const fields = [['measure', 'Measure'], ['grain', 'Grain'], ['basis', 'Basis'],
        ['period_start', 'Period start'], ['period_end', 'Period end']];
      for (const [key, title] of fields) identityFields.push(title + ' · ' + (evidence[key] || 'unknown'));
      const amount = evidence.total_amount || evidence.amount;
      if (amount) identityFields.push('Reported total · ' + [amount, evidence.currency].filter(Boolean).join(' '));
      if (entry.preview?.fields?.contributor_count) identityFields.push('Contributor count · ' + entry.preview.fields.contributor_count);
      if (evidence.manifest_ref) identityFields.push('Manifest reference · ' + evidence.manifest_ref);
    }
    if (entry.type === 'journal') {
      if (evidence.posting_date) identityFields.push('Posting date · ' + evidence.posting_date);
      if (evidence.schedule_id) identityFields.push('Schedule reference · ' + evidence.schedule_id);
    }

    return identityFields;
  }

  const actions = {
    source:'Capture source delivery', normalized:'Normalize source records', policy:'Assign commercial terms',
    calculation:'Run the billing engine', invoice:'Issue native document', aggregate:'Aggregate results',
    reporting:'Publish report', payable:'Issue approved payable', payout:'Record payout evidence',
    statement:'Build client statement', adjustment:'Issue reviewed correction', payment:'Apply confirmed cash',
    package:'Prepare mock accounting handoff', journal:'Record mock posting', event:'Capture approved event or request',
    unmapped:'Identify object type',
  };

  function creationFlow(entry, entries, {singleRecord = false} = {}) {
    const connected = [...new Map([...entry.upstream, ...entry.downstream].map(link => [link.node, link])).values()];
    const keyFor = kind => Object.keys(stages).find(key => stages[key][1].includes(kind));
    const anchor = keyFor(entry.type) || 'unmapped';
    const has = key => connected.some(link => stages[key][1].includes(entries[link.node].type));
    const ledger = ['package', 'journal'];
    const core = ['source', 'normalized', 'calculation'];
    const invoice = [...core, 'invoice'];
    const extraInputs = new Map([['calculation', {keys:['policy'], label:'Independent input'}]]);
    const tracks = [];
    let primary, title, rollupSource, context;
    const eventType = (entry.evidence.event_type || '').toLowerCase().replace(/[_-]+/g, ' ');
    const basis = [entry.evidence.measure, entry.evidence.basis].filter(Boolean).join(' ').toLowerCase().replace(/[-_]/g, ' ');
    const cashBasis = /\b(?:bank|cash|settlement|payments?|collected|journal|ledger)\b/.test(basis);

    if (anchor === 'aggregate') {
      if (cashBasis) {
        const posting = /\b(?:journal|ledger)\b/.test(basis);
        primary = [...invoice, ...(posting ? ledger : ['payment']), 'aggregate', 'reporting'];
        rollupSource = posting ? 'Aggregate journal postings' : 'Aggregate applied cash';
        title = posting ? 'Accounting rollup' : 'Cash application rollup';
        context = 'Confirm which cash applications or postings the measure includes.';
      } else if (/\binvoic(?:e|es|ed|ing)\b|\bissued originals\b/.test(basis)) {
        primary = [...invoice, 'aggregate', 'reporting'];
        rollupSource = 'Sum issued invoices';
        title = 'Invoice rollup';
        context = 'The supplied measure points to issued invoices. Confirm the contributor list and the calculation behind each invoice.';
      } else if (/\b(?:earned|earnings|entitlements?|accruals?|assessed|calculations?)\b/.test(basis)) {
        primary = [...core, 'aggregate', 'reporting'];
        rollupSource = 'Aggregate calculation results';
        title = 'Calculated earnings or fees';
        context = 'Confirm which results contribute to the rollup and which led to issued documents.';
      } else {
        primary = ['aggregate', 'reporting'];
        title = 'Rollup and report';
        context = 'The rollup basis is unclear. Request the measure definition and contributor list to determine its inputs.';
        extraInputs.set('aggregate', {keys:['calculation', 'invoice', 'payment'], label:'Possible inputs · confirm the rollup basis'});
      }
    } else if (anchor === 'payable' || anchor === 'payout' || (anchor === 'event' && eventType === 'payout request')) {
      primary = [...core, 'payable', 'payout'];
      title = 'Advisor earnings and payout';
      extraInputs.set('payout', {keys:['event'], label:'Payout request'});
      context = 'Payout needs an eligible payable and confirmation that cash moved.';
    } else if (anchor === 'event') {
      if (eventType === 'compensation entitlement') {
        primary = ['event', 'calculation', 'payable'];
        title = 'Compensation entitlement';
      } else if (eventType === 'one time charge' || eventType === 'one time credit') {
        primary = ['event', 'calculation', 'invoice'];
        title = 'One-time billing';
        context = 'Confirm the event approval, effective date and any original document it corrects.';
      } else {
        primary = ['event'];
        title = 'Confirm the event before choosing a process';
        context = 'Confirm what triggers the event and which step uses it.';
      }
    } else if (anchor === 'adjustment' || anchor === 'payment') {
      primary = [...invoice, anchor, ...ledger];
      title = anchor === 'payment' ? 'Invoice, cash application and accounting' : 'Invoice correction and accounting';
    } else if (ledger.includes(anchor) ||
        (anchor === 'reporting' && has('journal')) ||
        (anchor === 'invoice' && (has('journal') || has('package')))) {
      primary = [...invoice, ...ledger, 'reporting'];
      title = 'Invoice to accounting report';
      extraInputs.set('package', {keys:['adjustment','payment'], label:'Additional inputs when present'});
    } else if (anchor === 'reporting') {
      primary = ['reporting'];
      title = 'Report creation';
      extraInputs.set('reporting', {keys:['calculation','aggregate'], label:'Possible report inputs'});
    } else if (anchor === 'invoice' || anchor === 'statement') {
      primary = has('payable') && anchor === 'statement' ? [...core,'payable','statement'] : [...invoice,'statement'];
      title = 'Client statement';
    } else if (anchor === 'unmapped') {
      primary = ['unmapped'];
      title = 'Confirm the object before choosing a process';
      context = 'Choose an event type to place the supplied record in the flow.';
    } else {
      primary = core;
      title = 'Source to calculation';
      tracks.push({title:'Client billing', from:'calculation', keys:['invoice','statement']},
        {title:'Advisor earnings', from:'calculation', keys:['payable','payout']});
    }

    const shown = new Set();
    const contribution = singleRecord && rollupSource === 'Sum issued invoices' ? rollupContributor(entry) : null;
    function step(key) {
      const [stageTitle, kinds, ask] = stages[key];
      const isAnchor = key === anchor;
      const actual = isAnchor ? [] : connected.filter(link => kinds.includes(entries[link.node].type));
      actual.forEach(link => shown.add(link.node));
      const present = actual.some(link => entries[link.node].state === 'record present');
      const referenced = actual.some(link => entries[link.node].state === 'reference only');
      const example = key === 'invoice' && !present ? contribution : null;
      const input = extraInputs.get(key);
      return {key, title:stageTitle, action: key === 'aggregate' && rollupSource ? rollupSource : actions[key],
        kinds, ask, isAnchor, actual, example,
        state:present ? (referenced ? 'partial' : 'linked') : referenced ? 'reference' : example ? 'illustration' : 'expected',
        inputs:input && {label:input.label, steps:input.keys.map(step)}};
    }
    const process = [{title, keys:primary}, ...tracks].map(track => ({
      title:track.title, from:track.from && stages[track.from][0], steps:track.keys.map(step),
    }));
    const other = connected.filter(link => !shown.has(link.node)).map(link => {
      const node = entries[link.node];
      return {key:keyFor(node.type), title:node.label, kinds:[node.type], actual:[link],
        state:node.state === 'reference only' ? 'reference' : 'linked'};
    });
    return {process, other, context, identityFields:identityFieldsFor(entry)};
  }

  return {rollupContributor, creationFlow};
})();

if (typeof module !== 'undefined') module.exports = traceCycle;
