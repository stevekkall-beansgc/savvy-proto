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
  };
  const paths = {
    source: [[], ['normalized', 'calculation', 'aggregate?', 'invoice?', 'payable?']],
    normalized: [['source'], ['calculation', 'aggregate?', 'invoice?', 'payable?']],
    policy: [[], ['calculation', 'invoice?', 'payable?']],
    calculation: [['source?', 'normalized?', 'policy', 'event?'], ['aggregate?', 'invoice?', 'payable?']],
    invoice: [['source?', 'normalized?', 'policy', 'calculation', 'event?'], ['statement?', 'adjustment?', 'payment?', 'package?', 'journal?']],
    payable: [['event?', 'calculation'], ['statement?', 'payout?', 'journal?']],
    payout: [['event?', 'payable'], ['statement?', 'journal?']],
    statement: [['calculation', 'invoice?', 'payable?', 'aggregate?'], ['reporting?']],
    credit_memo: [['event?', 'invoice'], ['payment?', 'statement?', 'journal?']],
    debit_memo: [['event?', 'invoice'], ['payment?', 'statement?', 'journal?']],
    payment: [['invoice', 'adjustment?'], ['statement?', 'journal?']],
    journal: [['package?', 'invoice?', 'aggregate?', 'adjustment?', 'payment?', 'payout?'], ['reporting?']],
    accounting_package: [['invoice?', 'adjustment?', 'payment?'], ['journal?', 'reporting?']],
    report: [['calculation?', 'aggregate?', 'invoice?', 'journal?'], []],
    event: [['source?', 'policy?'], ['calculation?', 'invoice?', 'payable?', 'payout?']],
  };

  function plan(entry, entries) {
    const evidence = entry.evidence;
    let [upstream, downstream] = paths[entry.type] || [
      ['source?', 'normalized?', 'calculation?'], ['aggregate?', 'statement?', 'journal?'],
    ];
    let context = null;
    if (entry.type === 'source' || entry.type === 'normalized')
      context = 'Normalized data and independently assigned terms can meet at the calculation.';
    if (entry.type === 'aggregate') {
      const basis = [evidence.measure, evidence.basis].filter(Boolean).join(' ').toLowerCase().replace(/[-_]/g, ' ');
      if (/\b(?:bank|cash|settlement|payments?|collected|journal|ledger)\b/.test(basis)) {
        upstream = ['invoice?', 'payable?', 'payment?', 'payout?', 'journal?'];
        context = 'The measure or basis suggests cash or accounting activity. Confirm which events or postings the total includes.';
      } else if (/\binvoic(?:e|es|ed|ing)\b|\bissued originals\b/.test(basis)) {
        upstream = ['source', 'normalized', 'policy', 'calculation', 'invoice'];
        context = 'The measure or basis suggests an invoice rollup. Confirm the contributing invoices and calculation results.';
      } else if (/\b(?:earned|earnings|entitlements?|accruals?|assessed|calculations?)\b/.test(basis)) {
        upstream = ['source?', 'normalized?', 'policy?', 'calculation', 'payable?'];
        context = 'The measure or basis suggests earned or assessed amounts. Confirm the contributing results and whether they created a payable.';
      } else {
        upstream = ['source?', 'normalized?', 'policy?', 'calculation?', 'invoice?', 'payment?'];
        context = 'The rollup basis is unclear. It could summarize fee results, issued invoices, or cash activity. Ask for the measure definition and contributor list.';
      }
      downstream = ['reporting?', 'statement?', 'invoice?', 'journal?'];
      if (entry.upstream.some(link => entries[link.node].type === 'invoice') || upstream.includes('invoice'))
        downstream = downstream.filter(stage => stage !== 'invoice?');
    }
    if (entry.type === 'event') {
      const kind = (evidence.event_type || '').toLowerCase().replace(/[_-]+/g, ' ');
      if (kind === 'payout request') {
        upstream = ['payable'];
        downstream = ['payout?', 'journal?'];
        context = 'A payout request still needs eligibility and confirmed cash movement before it can reduce a payable.';
      } else if (kind === 'compensation entitlement') {
        downstream = ['calculation', 'payable', 'statement?', 'payout?'];
        context = 'An entitlement may enter the calculation for earned compensation.';
      } else if (kind === 'one time charge' || kind === 'one time credit') {
        upstream = ['source?', 'policy', 'invoice?'];
        downstream = ['calculation', 'invoice?', 'statement?', 'journal?'];
        context = 'A one-time event can enter the billing calculation. Check the approval, effective date and any original document it corrects.';
      } else {
        context = 'This event type needs a workflow check. Confirm what triggers it and what consumes it.';
      }
    }
    if (entry.type === 'unmapped') {
      context = 'The record has no reliable cycle position yet. These are possible areas to investigate. Choose an event type to narrow the map.';
    }

    function stageCards(keys, direction) {
      const connections = entry[direction];
      const shown = new Set();
      const cards = keys.map(key => {
        const conditional = key.endsWith('?');
        const [title, kinds, ask] = stages[key.replace(/\?$/, '')];
        const actual = connections.filter(link => kinds.includes(entries[link.node].type));
        actual.forEach(link => shown.add(link.node));
        const present = actual.some(link => entries[link.node].state === 'record present');
        const referenced = actual.some(link => entries[link.node].state === 'reference only');
        const state = referenced ? (present ? 'partial' : 'reference') : present ? 'linked' : conditional ? 'conditional' : 'expected';
        return {title, state, ask, actual, kinds};
      });
      for (const link of connections.filter(link => !shown.has(link.node)).slice(0, 5)) {
        const node = entries[link.node];
        cards.push({title: node.label, kinds: [node.type], state: node.state === 'reference only' ? 'reference' : 'linked',
          ask: 'Confirm the record’s scope and how the two records are related.', actual: [link]});
      }
      return cards;
    }

    const identityFields = [];
    if (!entry.id) identityFields.push('Record ID · unknown');
    if (entry.type === 'aggregate') {
      const fields = [['measure', 'Measure'], ['grain', 'Grain'], ['basis', 'Basis'],
        ['period_start', 'Period start'], ['period_end', 'Period end']];
      for (const [key, title] of fields) identityFields.push(title + ' · ' + (evidence[key] || 'unknown'));
      const amount = evidence.total_amount || evidence.amount;
      if (amount) identityFields.push('Reported total · ' + [amount, evidence.currency].filter(Boolean).join(' '));
      if (evidence.manifest_ref) identityFields.push('Manifest reference · ' + evidence.manifest_ref);
    }
    if (entry.type === 'journal') {
      if (evidence.posting_date) identityFields.push('Posting date · ' + evidence.posting_date);
      if (evidence.schedule_id) identityFields.push('Schedule reference · ' + evidence.schedule_id);
    }

    return {
      context,
      upstream: stageCards(upstream, 'upstream'),
      downstream: stageCards(downstream, 'downstream'),
      anchorAsk: Object.values(stages).find(([, kinds]) => kinds.includes(entry.type))?.[2],
      identityFields,
    };
  }

  return {plan};
})();

if (typeof module !== 'undefined') module.exports = traceCycle;
