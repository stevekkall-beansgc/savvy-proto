'use strict';

const traceDimensions = (() => {
  // Coverage is scoped to the reviewed contracts. Raw bytes and generic maps can hold
  // fields outside this list without establishing a typed dimension or its lineage.
  const catalog = [
    ['Billing entity', 'entity|entity_id|billing_entity_id', 'carried',
      'Silver and Gold scope → native billing scope → accounting acceptance and Finance mart.',
      'Scope in Silver. Confirm the effective-dated crosswalk to the Campfire ledger entity.',
      'source normalized calculation invoice journal accounting_package'],
    ['Ledger entity or subsidiary', 'legal_entity|legal_entity_id|subsidiary|subsidiary_id|ledger_entity|ledger_entity_id|company_code', 'missing',
      'The reviewed mock posting contract has billing scope and no distinct ledger entity or subsidiary field.',
      'Finance should version the billing-entity-to-ledger-entity crosswalk and retain the selected entity on each posting.',
      'accounting_package journal'],
    ['Billing product', 'product|product_id|product_code|billing_product|billing_product_id|product_line', 'dropped',
      'Silver policy assignment has product ID. Native allocation, invoice-line and accounting outputs lack an explicit per-line product ID.',
      'Assign in Silver, freeze the product ID for the service period, then carry it through Gold, billing allocation and the relevant projection.',
      'policy calculation aggregate invoice payable report journal accounting_package statement'],
    ['Billing subject', 'billing_subject|billing_subject_id|subject_id', 'carried',
      'Silver and Gold scope → document or payable → accounting package header.',
      'Resolve the billing subject in Silver and retain its scoped identity through billing.',
      'normalized policy calculation invoice payable event'],
    ['Source provider', 'provider|provider_id|custodian|custodian_id|source_provider_id', 'partial',
      'Raw delivery and Silver mapping carry source evidence. Gold retains source references that can be joined to delivery and mapping.',
      'Capture the provider key on ingestion. Carry it as a scoped Silver ID or preserve the join if a report groups by provider.',
      'source normalized'],
    ['Customer', 'customer|customer_id|billing_customer_id|client_id', 'dropped',
      'Silver account roster → Gold input manifest → native obligation and invoice-line mart. Accounting package lines omit customer ID.',
      'Resolve in Silver. Carry the effective-dated ID per allocation or preserve a scoped join before aggregating.',
      'source normalized calculation aggregate invoice report journal accounting_package statement'],
    ['Custodial account', 'custodial_account|custodial_account_id|billing_account_id|investment_account_id', 'dropped',
      'Silver account roster → Gold calculation → native obligation and invoice-line mart. Accounting package lines omit account ID.',
      'Normalize provider account identity in Silver. Retain the scoped ID or a line-level bridge when rolling up.',
      'source normalized calculation invoice report accounting_package'],
    ['Advisor or broker', 'advisor|advisor_id|broker|broker_id|advisor_code|broker_code', 'dropped',
      'Native obligations carry broker ID. The native invoice-line mart and accounting package omit it as an explicit dimension.',
      'Derive from effective-dated advisor and account ownership in Silver. Snapshot the owner on the allocation or obligation and expose it downstream.',
      'source normalized invoice payable payout report journal accounting_package statement'],
    ['Service period', 'service_period|service_start|service_end|service_end_exclusive|service_period_start|service_period_end', 'carried',
      'Gold results → native obligation and invoice line → accounting package lines. The snapshot rollup also exposes service dates.',
      'Freeze service dates on the obligation. Carry both dates through projections and label posting and recognition dates separately.',
      'source normalized policy calculation aggregate invoice payable report statement'],
    ['Posting period', 'posting_period|fiscal_period|accounting_period', 'carried',
      'Native billing and cash carry posting period. Accounting package retains it independently of service dates.',
      'Finance assigns an open period before packaging or applying cash. Preserve the period selected for the posting.',
      'invoice payment journal accounting_package report'],
    ['Posting date', 'posting_date|posted_on|journal_date|ledger_date', 'partial',
      'Normalized accounting evidence has a source date. The reviewed Finance mart does not expose a distinct ledger posting date.',
      'Capture the reported posting date in normalized accounting evidence and project it separately from the package period and ingestion time.',
      'journal'],
    ['Recognition schedule and period', 'schedule_id|recognition_schedule_id|recognition_schedule_period|recognition_period', 'partial',
      'Mock accounting acceptance retains period and amount on schedule rows. The Finance mart exposes recognized and deferred totals at acceptance grain.',
      'Carry the supplied schedule ID, periods, amounts and revisions from accounting ingestion through a recognition schedule projection.',
      'journal accounting_package'],
    ['Fee or revenue code', 'fee_code|fee_type|fee_category|fee_component|revenue_code|revenue_type|revenue_category', 'missing',
      'The reviewed Gold projection has component and output class. It has no dedicated commercial fee code contract through native allocations and posting.',
      'Define a stable commercial fee code in policy output metadata, then carry it on Gold details and allocations before aggregation.',
      'policy calculation aggregate invoice report journal accounting_package statement'],
    ['Billing component', 'component|output_class|output_role|charge_component', 'carried',
      'Gold detail and the reporting snapshot retain component, output role and output class.',
      'Assign in policy output and preserve the component through rollups. Confirm the report groups terminal results at the intended grain.',
      'calculation aggregate'],
    ['General ledger account', 'gl_account|gl_account_id|gl_account_code|general_ledger_account|general_ledger_account_id|general_ledger_account_code', 'missing',
      'The reviewed mock package and accounting acceptance have no typed GL account per journal line.',
      'Finance maps commercial fee code, entity and treatment to GL accounts. Retain the actual account at journal-line grain.',
      'journal accounting_package report'],
    ['Cost center', 'cost_center|cost_center_id|cost_center_code', 'missing',
      'Generic account dimensions can carry a tag. The reviewed package and Finance projection have no named cost center contract.',
      'Resolve a commercial cost center in Silver from the effective-dated master. Use the Finance posting map for a ledger-only cost center.',
      'journal accounting_package report'],
    ['Department', 'department|department_id|department_code', 'missing',
      'The reviewed posting and Finance contracts have no named department field.',
      'Resolve the effective-dated department in Silver for commercial ownership, or in the Finance map for a ledger-only segment.',
      ''],
    ['Business unit', 'business_unit|business_unit_id|business_unit_code', 'missing',
      'The reviewed native allocation and Finance contracts have no named business unit dimension.',
      'Resolve ownership in Silver and snapshot it at allocation grain. Confirm any separate rollup in the Finance map.',
      ''],
    ['Profit center', 'profit_center|profit_center_id|profit_center_code', 'missing',
      'The reviewed mock posting and Finance contracts have no named profit center dimension.',
      'Finance should version the ledger profit center mapping, then carry the code on posting lines.',
      ''],
    ['Currency', 'currency|currency_code|iso_currency', 'carried',
      'Silver observations → Gold results → native obligations and accounting package. The prototype exercises USD on this path.',
      'Normalize currency at ingestion and retain it on every money-bearing fact, aggregate and document.',
      'source normalized calculation aggregate invoice payable payout payment report journal'],
  ].map(([dimension, aliases, status, contract, assignment, probes]) => ({
    dimension, aliases: aliases.split('|'), status, contract, assignment, probes: probes.split(' '),
  }));

  const containers = new Set(['dimensions', 'segments', 'custom_fields', 'tags', 'attributes']);
  const coverageLabels = {
    carried:'Carried in reviewed stages', dropped:'Captured upstream · dropped from a handoff',
    missing:'No typed field in reviewed path', partial:'Partially carried', review:'Meaning or mapping uncertain',
  };
  const declarationKeys = ['columns', 'group_by', 'groupBy', 'report_dimensions', 'dimension_keys'];
  const fieldKey = value => value.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

  function observe(record) {
    const fields = new Map(), pending = [{value: record, path: []}];
    for (let count = 0; pending.length && count < 6000; count++) {
      const {path, value} = pending.pop();
      if (Array.isArray(value) && path.length < 7) {
        for (const child of value.slice(0, 100).reverse()) pending.push({path: [...path, '[]'], value: child});
      } else if (value && typeof value === 'object' && path.length < 7) {
        for (const [key, child] of Object.entries(value).slice(0, 160).reverse())
          pending.push({path: [...path, key.slice(0, 120)], value: child});
      } else if (path.length && value !== null && typeof value !== 'object' &&
                 String(value).trim() && fields.size < 250) {
        fields.set(JSON.stringify(path), path);
      }
    }
    return [...fields.values()];
  }

  function declared(record) {
    const names = declarationKeys.flatMap(key => Array.isArray(record[key]) ? record[key].slice(0, 100) : []);
    return [...new Set(names.filter(name => typeof name === 'string' && name.trim()).map(name => name.trim().slice(0, 120)))].slice(0, 100);
  }

  function match(path, isDeclaration, type) {
    const keys = path.filter(key => key !== '[]').map(fieldKey);
    const last = keys.at(-1), parent = keys.at(-2);
    if (!last) return null;
    const options = [last];
    if (['id', 'code'].includes(last) && parent) options.push(parent + '_' + last);
    if (last === 'period' && keys.includes('schedule')) options.push('recognition_schedule_period');
    if (options.includes('account_id') && ['source', 'normalized', 'policy', 'calculation', 'invoice', 'statement'].includes(type))
      options.push('custodial_account_id');
    const candidate = catalog.find(item => item.aliases.some(alias => options.includes(alias)));
    if (candidate) return candidate;
    if (options.includes('account_id')) {
      return {dimension:'Account ID meaning', status:'review', contract:'The label can refer to a ledger account or a commercial account.',
        assignment:'Confirm the source key and grain. Map ledger accounts at Finance and commercial accounts in Silver.'};
    }
    if (/^(?:id|name|value|total|amount|count|quantity|balance)$|(?:^|_)(?:amount|minor|count|quantity|total|balance)(?:_|$)/.test(last)) return null;
    const inDimensionObject = keys.slice(0, -1).some(key => containers.has(key));
    const looksLikeDimension = /(?:^|_)(?:segment|tag|desk|region|channel|business_unit|program)(?:_|$)/.test(last);
    if (!isDeclaration && !inDimensionObject && !looksLikeDimension) return null;
    const field = ['id', 'code'].includes(last) && parent && !containers.has(parent) ? parent : last;
    return {dimension:'Unreviewed field · ' + field.replaceAll('_', ' '), status:'review',
      contract:'This label has no confirmed meaning or mapping in the reviewed profile.',
      assignment:'Ask which report uses this field, its grain and the system of record. Resolve commercial dimensions in Silver and ledger-only dimensions in the Finance map.'};
  }

  function describe(node) {
    return [node.label, node.id].filter(Boolean).join(' · ');
  }

  function review(anchor, entries, {includeAll = false} = {}) {
    const nodes = new Map([[anchor.node, anchor]]);
    const queue = [{entry:anchor, distance:0}];
    for (let index = 0; index < queue.length && nodes.size < 61; index++) {
      const {entry, distance} = queue[index];
      if (distance >= 8) continue;
      for (const edge of [...entry.upstream, ...entry.downstream]) {
        if (edge.distance !== 1 || nodes.has(edge.node) || entries[edge.node].state !== 'record present') continue;
        nodes.set(edge.node, entries[edge.node]);
        queue.push({entry:entries[edge.node], distance:distance + 1});
        if (nodes.size === 61) break;
      }
    }
    const supplied = [...nodes.values()].filter(node => node.state !== 'reference only');
    const inventory = new Map(), byNode = new Map(), declarationsByNode = new Map();
    for (const node of supplied) {
      const observed = new Set();
      byNode.set(node.node, observed);
      const declarations = new Set();
      declarationsByNode.set(node.node, declarations);
      const fields = (node.observed_fields || []).map(path => ({path, declared: false}));
      for (const name of node.declared_dimensions || []) fields.push({path:[name], declared:true});
      for (const field of fields) {
        const item = match(field.path, field.declared, node.type);
        if (!item) continue;
        const dimension = item.dimension;
        const row = inventory.get(dimension) || {...item, fields:[], handoffs:[]};
        (field.declared ? declarations : observed).add(dimension);
        if (row.fields.length < 60) row.fields.push({
          point:describe(node), path:field.path.join('.').replaceAll('.[]', '[]'), declared:field.declared,
        });
        inventory.set(dimension, row);
      }
    }

    for (const before of supplied) {
      if (before.state !== 'record present') continue;
      for (const edge of before.downstream) {
        const after = nodes.get(edge.node);
        if (edge.distance !== 1 || !after || after.state !== 'record present' || !Array.isArray(after.observed_fields)) continue;
        const afterObserved = byNode.get(after.node), afterDeclared = declarationsByNode.get(after.node);
        if (after.type === 'report' && afterDeclared.size && !afterObserved.size) continue;
        for (const dimension of byNode.get(before.node)) {
          if (afterObserved.has(dimension) || afterDeclared.has(dimension)) continue;
          const row = inventory.get(dimension);
          if (row.handoffs.length >= 12) continue;
          row.handoffs.push({
            before:describe(before), after:describe(after),
            verify: ['aggregate', 'report'].includes(after.type) ? 'Check the grouping keys or detail projection.' :
              'Check field mapping, report selection and comparable line grain.',
          });
        }
      }
    }
    const rows = [];
    for (const item of catalog) {
      const observed = inventory.get(item.dimension);
      if (observed || includeAll || item.probes.includes(anchor.type))
        rows.push(observed || {...item, fields:[], handoffs:[]});
    }
    return [...rows, ...[...inventory.values()].filter(row => row.status === 'review').slice(0, 24)];
  }

  function gapRows(anchor, dimensions) {
    const descriptions = {
      missing: ['Prototype field gap', 'Confirm this is a report dimension. Identify its owner, grain, and effective date.'],
      dropped: ['Prototype handoff gap', 'Compare the upstream and downstream contracts and confirm which keys the report needs.'],
      partial: ['Partial prototype coverage', 'Check the available fields against the actual report at its required grain.'],
      review: ['Field definition to confirm', 'Ask which report uses the field and show its source, definition, and owner.'],
    };
    return dimensions.flatMap(item => {
      const fields = item.fields.map(field => `${field.declared ? 'Declared' : 'Observed'} · ${field.path} (${field.point})`).join('\n') ||
        'Unseen in supplied records';
      const base = [describe(anchor), item.dimension];
      const evidence = [coverageLabels[item.status], item.contract, fields, item.assignment];
      const finding = descriptions[item.status];
      const rows = finding ? [[...base, finding[0], ...evidence, '', '', finding[1], 'Open']] : [];
      for (const hop of item.handoffs) {
        rows.push([...base, 'Possible loss in supplied handoff', ...evidence, hop.before, hop.after, hop.verify, 'Open']);
      }
      return rows;
    });
  }

  function gapCsv(rows) {
    const headers = ['Starting record', 'Dimension', 'Finding', 'Prototype coverage', 'Prototype evidence', 'Supplied field paths',
      'Recommended assignment or carry-forward', 'Upstream record', 'Downstream record', 'What to confirm', 'Review status'];
    const quote = value => {
      const text = String(value).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
      const safe = /^(?:[\s\uFEFF]*[=+\-@]|[\t\r\n])/.test(text) ? "'" + text : text;
      return '"' + safe.replaceAll('"', '""') + '"';
    };
    return [headers, ...rows].map(row => row.map(quote).join(',')).join('\r\n') + '\r\n';
  }

  return {observe, declared, review, gapRows, gapCsv, coverageLabels};
})();

if (typeof module !== 'undefined') module.exports = traceDimensions;
