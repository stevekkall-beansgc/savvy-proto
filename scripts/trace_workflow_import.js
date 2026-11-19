'use strict';

function createTraceImport(config) {
  const own = (object, key) => Object.hasOwn(object, key);
  const dimensions = typeof module !== 'undefined' ? require('./trace_workflow_dimensions.js') : traceDimensions;
  const previews = typeof module !== 'undefined' ? require('./trace_workflow_previews.js') : tracePreviews;
  const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const words = value => String(value).replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().replace(/[_-]+/g, ' ').trim();
  const slug = value => words(value).replace(/\s+/g, '_');
  const ref = value => {
    if (isObject(value)) value = get(value, 'id');
    if (typeof value !== 'string' && !Number.isSafeInteger(value)) return null;
    return /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/.test(String(value)) ? String(value) : null;
  };
  const get = (object, key) => isObject(object) && own(object, key) ? object[key] : undefined;
  const idKey = (kind, id) => JSON.stringify([kind, id]);
  const eventKinds = {
    one_time_charge: 'One-time charge',
    one_time_credit: 'One-time credit',
    compensation_entitlement: 'Compensation entitlement',
    payout_request: 'Payout request',
  };
  const roleAliases = {
    ...config.kind_hints,
    source: ['source delivery', 'source event', 'balance observation', 'custody delivery', 'raw event'],
    normalized: ['normalized fact', 'balance fact', 'normalized record'],
    policy: ['policy assignment', 'rate assignment', 'terms assignment'],
    calculation: ['fee calculation', 'billing calculation', 'fee result', 'calculation result'],
    aggregate: [...config.kind_hints.aggregate, 'billing aggregate', 'billing summary', 'billing rollup'],
    invoice: [...config.kind_hints.invoice, 'billing document'],
    payment: [...config.kind_hints.payment, 'payment application'],
    journal: [...config.kind_hints.journal, 'journal entry', 'recognition schedule'],
    event: ['billing event', ...Object.values(eventKinds).map(words)],
    payable: ['advisor payable', 'earnings payable'],
    payout: ['payout confirmation', 'payout settlement', 'payout or settlement'],
    accounting_package: ['posting package', 'accounting input package'],
    report: ['finance report', 'report export', 'report or export'],
  };
  const roleIds = {...config.record_ids, source: 'delivery id|source record id|observation id',
    normalized: 'fact id|normalized record id|normalized fact id', policy: 'assignment id|policy assignment id',
    calculation: 'calculation id|calculation result id|charge calculation id', event: 'event id|billing event id',
    payable: 'payable id|advisor payable id', payout: 'payout id|payout settlement id',
    accounting_package: 'accounting package id|posting package id', report: 'report id|report key',
    aggregate: 'aggregate id|rollup id|report rollup id'};
  const aliasOverrides = {event_type: 'event type|event kind|event name', ...config.aliases};

  function parseCsv(text) {
    const lines = [];
    let row = [], field = '', quoted = false, closed = false;
    const endField = () => { row.push(field); field = ''; closed = false; };
    const endRow = () => {
      endField();
      if (row.some(value => value.trim())) lines.push(row);
      if (lines.length > 501) throw Error('A CSV file can contain up to 500 rows.');
      row = [];
    };
    for (let index = 0; index < text.length; index++) {
      const character = text[index];
      if (quoted) {
        if (character !== '"') field += character;
        else if (text[index + 1] === '"') { field += '"'; index++; }
        else { quoted = false; closed = true; }
      } else if (character === ',') endField();
      else if (character === '\n' || character === '\r') {
        if (character === '\r' && text[index + 1] === '\n') index++;
        endRow();
      } else if (closed || (character === '"' && field)) throw Error('The CSV contains an invalid quoted field.');
      else if (character === '"') quoted = true;
      else field += character;
    }
    if (quoted) throw Error('The CSV has an unclosed quoted field.');
    if (field || row.length || closed) endRow();
    const headers = lines.shift()?.map(value => value.trim());
    if (!headers?.length || headers.some(header => !header) || new Set(headers).size !== headers.length)
      throw Error('The CSV needs a unique name for each column.');
    if (lines.some(values => values.length !== headers.length)) throw Error('CSV rows must match the header columns.');
    return lines.length ? lines.map(values => Object.fromEntries(headers.map((header, index) => [header, values[index]]))) :
      {kind: 'report', columns: headers};
  }

  function parse(text, name) {
    text = text.replace(/^\uFEFF/, '');
    if (!text.trim()) throw Error('This file is empty.');
    if (name.toLowerCase().endsWith('.csv')) return parseCsv(text);
    if (!name.toLowerCase().endsWith('.json')) throw Error('Choose a JSON or CSV export.');
    // Keep original number literals where available. IDs and amounts are evidence, never calculated here.
    return JSON.parse(text, (_, value, context) => typeof value === 'number' && context?.source
      ? context.source : value);
  }

  function records(payload) {
    const rows = [], links = [], lineage = [];
    const groups = new Map(Object.entries(config.groups).map(([kind, group]) => [group, kind]));
    function visit(value, path, hint = '') {
      if (path.length > 8) throw Error('Choose an export with records nested no more than eight levels.');
      if (Array.isArray(value)) {
        for (const [index, item] of value.entries()) visit(item, [...path, index], hint);
        return;
      }
      if (!isObject(value)) throw Error('Choose an object or an array of record objects.');
      const entries = Object.entries(value);
      const sections = entries.filter(([key, item]) => (groups.has(key) || key === 'entries') &&
        (Array.isArray(item) || isObject(item)));
      const isBundle = !get(value, 'id') && !get(value, 'kind') && !get(value, 'event_type') &&
        (sections.length || Array.isArray(get(value, 'links')) || Array.isArray(get(value, 'lineage')));
      if (isBundle && !hint) {
        if (Array.isArray(get(value, 'links'))) links.push(...value.links.slice(0, 6001));
        if (Array.isArray(get(value, 'lineage'))) lineage.push(...value.lineage.slice(0, 2001));
        for (const [key, item] of sections) {
          if (Array.isArray(get(item, 'results'))) visit(item.results, [...path, key, 'results'], groups.get(key));
          else visit(item, [...path, key], groups.get(key));
        }
        return;
      }
      if (!hint && !get(value, 'id') && !get(value, 'kind')) {
        const wrappers = entries.filter(([key, item]) => ['results', 'records', 'data', 'events', 'payload', 'rows'].includes(key) &&
          (isObject(item) || Array.isArray(item)));
        if (wrappers.length === 1) {
          const [key, item] = wrappers[0];
          visit(item, [...path, key]);
          return;
        }
        if (entries.length === 1 && !groups.has(entries[0][0]) && (isObject(entries[0][1]) || Array.isArray(entries[0][1]))) {
          const [key, item] = entries[0];
          visit(item, [...path, key]);
          return;
        }
      }
      if (rows.length >= 500) throw Error('A file can contain up to 500 records.');
      rows.push({raw: value, path, hint});
    }
    visit(payload, []);
    if (!rows.length && !links.length && !lineage.length) throw Error('No record objects or trace links were found.');
    return {rows, links, lineage};
  }

  function leaves(object) {
    const result = [];
    function visit(value, path) {
      for (const [name, item] of Object.entries(value)) {
        if (result.length >= 150) break;
        const next = [...path, name];
        if (isObject(item) && next.length < 5) visit(item, next);
        else if (typeof item === 'string' || typeof item === 'number') result.push({path: next, value: item});
      }
    }
    visit(object, []);
    return result;
  }

  function at(object, path) {
    return path?.reduce(get, object);
  }

  function suggest(row) {
    const path = row.path.filter(key => typeof key === 'string').at(-1);
    const isLabel = value => typeof value === 'string' && value.trim();
    const declaredEvent = [get(row.raw, 'event_type'), get(row.raw, 'eventType'), get(row.raw, 'event_kind')].find(isLabel);
    const declaredKind = [get(row.raw, 'kind'),
      get(row.raw, 'type'), get(row.raw, 'objectType'), get(row.raw, 'documentType')]
      .find(isLabel) || '';
    const exactKind = slug(declaredKind);
    if (own(config.types, exactKind) && exactKind !== 'event' && exactKind !== 'unmapped') {
      return {kind: exactKind, eventType: declaredEvent?.slice(0, 120) || '', basis: 'Declared record type'};
    }
    const eventType = slug(declaredEvent || declaredKind);
    if (own(eventKinds, eventType)) return {kind: 'event', eventType: eventKinds[eventType], basis: 'Declared event type'};
    if (row.hint) return {kind: row.hint, eventType: '', basis: 'Export section'};
    if (declaredEvent || declaredKind) {
      const type = declaredEvent || declaredKind;
      const value = words(type);
      const role = Object.keys(roleAliases).find(kind => value === words(kind) || roleAliases[kind].includes(value));
      return {kind: role || 'event', eventType: role ? '' : type.slice(0, 120), basis: 'Declared type'};
    }
    const names = new Set(row.fields.map(({path}) => words(path.at(-1))));
    const invoiceShape = (names.has('invoice number') || names.has('bill number')) &&
      !names.has('invoice id') && !names.has('invoice reference');
    const clues = [];
    for (const [kind, aliases] of Object.entries(roleIds)) {
      if (kind === 'invoice') continue; // An invoice ID alone may identify the parent of another record.
      if (aliases.split('|').some(alias => names.has(alias) && alias !== 'memo id')) clues.push(kind);
    }
    if (invoiceShape) clues.push('invoice');
    if (names.has('payment type') && !clues.includes('payment')) clues.push('payment');
    if (names.has('invoice line id') && path && /statement/i.test(path) && !clues.includes('statement')) clues.push('statement');
    if ((names.has('metric') || names.has('metric name') || names.has('measure')) &&
        (names.has('aggregation grain') || names.has('grain') || names.has('grouped by')) && !clues.includes('aggregate')) clues.push('aggregate');
    // Invoice and payment records can carry journal/assignment/FK fields. Prefer their own document shape.
    if (invoiceShape && !clues.some(kind => ['payment', 'credit_memo', 'debit_memo', 'statement'].includes(kind)))
      return {kind: 'invoice', eventType: '', basis: 'Invoice number without a parent invoice field'};
    if (clues.length === 1) return {kind: clues[0], eventType: '', basis: 'Matching field names'};
    return {kind: '', eventType: '', basis: clues.length ? 'More than one type fits these fields' : 'No reliable type match'};
  }

  const commonFields = ['id', 'entity', 'currency', 'period_start', 'period_end'];
  const roleFields = {
    source: ['source', 'source_id'], normalized: ['source', 'source_id'], policy: ['agreement_ref'],
    calculation: ['assignment_id', 'input_manifest_id', 'amount', 'amount_minor'],
    aggregate: ['measure', 'grain', 'basis', 'definition_ref', 'manifest_ref', 'total_amount', 'record_count'],
    invoice: ['invoice_number', 'source', 'source_id', 'journal_entry', 'total_amount', 'amount_due'],
    statement: ['invoice_id', 'invoice_number', 'invoice_line_id', 'amount'],
    payment: ['invoice_id', 'invoice_number', 'cash_confirmation_id', 'amount', 'amount_minor'],
    credit_memo: ['invoice_id', 'invoice_number', 'applied_amount', 'amount', 'amount_minor'],
    debit_memo: ['invoice_id', 'invoice_number', 'applied_amount', 'amount', 'amount_minor'],
    journal: ['invoice_id', 'invoice_number', 'posting_date', 'posting_period', 'schedule_id', 'amount'],
    event: ['source', 'source_id', 'economic_date', 'posting_period', 'original_id', 'revision', 'amount', 'amount_minor'],
    payable: ['economic_date', 'amount', 'amount_minor', 'input_manifest_id'],
    payout: ['economic_date', 'amount', 'amount_minor', 'cash_confirmation_id'],
    accounting_package: ['posting_period', 'amount_minor', 'source_id'],
    report: ['measure', 'grain', 'basis', 'definition_ref', 'manifest_ref', 'record_count'],
  };

  function fieldNames(kind) {
    return [...commonFields, ...(roleFields[kind] || [])];
  }

  function candidates(row, field) {
    const canonical = words(field);
    const aliases = new Set([canonical, ...(aliasOverrides[field] || '').split('|').filter(Boolean)]);
    if (field === 'id') for (const name of (roleIds[row.kind] || '').split('|')) aliases.add(name);
    return row.fields.map(({path}, index) => {
      const name = words(path.at(-1));
      const qualified = path.length > 1 ? words(path.at(-2)) + ' ' + name : '';
      const direct = aliases.has(name) && (name !== 'id' || path.length === 1);
      const score = path.length === 1 && name === canonical ? 3 : direct ? 2 : aliases.has(qualified) ? 1 : 0;
      return {index, score};
    }).filter(option => option.score).sort((a, b) => b.score - a.score);
  }

  function setKind(row, kind) {
    row.kind = kind;
    row.mapping = Object.create(null);
    for (const field of fieldNames(kind)) {
      const [first, second] = candidates(row, field);
      if (first && first.score !== second?.score) row.mapping[field] = first.index;
    }
    const collisions = Object.values(row.mapping).filter((value, index, values) => values.indexOf(value) !== index);
    for (const field of Object.keys(row.mapping)) if (collisions.includes(row.mapping[field])) delete row.mapping[field];
  }

  function prepare(record, filename, index) {
    const row = {...record, filename, index, fields: leaves(record.raw)};
    const suggested = suggest(row);
    Object.assign(row, suggested);
    setKind(row, suggested.kind);
    return row;
  }

  function mapped(row) {
    const evidence = Object.create(null);
    const inUse = new Set();
    for (const field of fieldNames(row.kind)) {
      const option = row.fields[row.mapping[field]];
      if (!option) continue;
      if (inUse.has(option)) throw Error('Use a source field for only one purpose on a record.');
      inUse.add(option);
      const value = option.value;
      if (field === 'currency') {
        if (/^[A-Z]{3}$/.test(String(value))) evidence[field] = value;
      } else if (config.measures.includes(field)) {
        const numeric = String(value);
        if (/^-?\d{1,20}(?:\.\d{1,12})?$/.test(numeric)) evidence[field] = numeric;
      } else if (config.descriptors.includes(field)) {
        if (String(value).trim()) evidence[field] = String(value).trim().slice(0, 120);
      } else if (ref(value)) evidence[field] = ref(value);
    }
    if (row.eventType.trim()) evidence.event_type = row.eventType.trim().slice(0, 120);
    return evidence;
  }

  function build(rows, importedLinks, reviewedLinks, lineage, fileCount, {preview = false} = {}) {
    if (!rows.length) throw Error('Add at least one record to run the trace.');
    if (rows.some(row => !row.kind)) throw Error('Choose an event type for each unclassified record.');
    if (rows.some(row => row.kind === 'event' && !row.eventType.trim())) throw Error('Enter a name for each custom event type.');
    const nodes = [], byKey = new Map(), collisions = new Set(), edges = new Map(), gaps = [];
    const counts = new Map();
    for (const row of rows) {
      const evidence = mapped(row);
      const id = evidence.id || null;
      delete evidence.id;
      const node = {node: nodes.length, type: row.kind, label: config.types[row.kind], id, evidence, classification: row.basis,
        state: 'record present', gaps: [], upstream: [], downstream: [], guidance: []};
      node.observed_fields = dimensions.observe(row.raw);
      node.preview = previews.capture(row.raw, row.kind, config.preview_profiles);
      if (row.kind === 'report' || row.kind === 'aggregate') node.declared_dimensions = dimensions.declared(row.raw);
      nodes.push(node);
      if (!id) {
        node.state = 'ambiguous identity';
        node.gaps.push('Choose a stable record ID to connect this entry.');
      } else {
        const key = idKey(row.kind, id);
        if (byKey.has(key)) {
          collisions.add(key);
          const first = byKey.get(key);
          first.state = node.state = 'ambiguous identity';
          const note = 'Multiple records share this type and ID. Resolve the duplicate before linking.';
          if (!first.gaps.includes(note)) first.gaps.push(note);
          node.gaps.push(note);
        } else byKey.set(key, node);
      }
      counts.set(row.kind, (counts.get(row.kind) || 0) + 1);
    }

    function resolve(pointer) {
      const kind = get(pointer, 'kind'), id = ref(get(pointer, 'id'));
      if (typeof kind !== 'string' || !own(config.types, kind) || kind === 'unmapped' || !id) return null;
      const key = idKey(kind, id);
      if (collisions.has(key)) {
        gaps.push('A relationship points to a duplicate record ID. Confirm the record version or scope.');
        return null;
      }
      if (!byKey.has(key)) {
        if (nodes.length >= 3000) throw Error('Narrow this review to fewer referenced records.');
        const node = {node: nodes.length, type: kind, label: config.types[kind], id, evidence: {}, state: 'reference only',
          gaps: ['Retrieve the referenced record and confirm the ID and scope.'], upstream: [], downstream: [], guidance: []};
        byKey.set(key, node);
        nodes.push(node);
      }
      return byKey.get(key);
    }

    function link(left, right, basis) {
      if (!left || !right || left === right) return;
      if (left.state === 'ambiguous identity' || right.state === 'ambiguous identity') {
        gaps.push('A relationship requires a stable, unique ID for both records.');
        return;
      }
      const scopes = ['entity', 'currency'];
      if (left.type === 'invoice' && ['payment', 'credit_memo', 'debit_memo', 'statement', 'journal'].includes(right.type))
        scopes.push('invoice_number');
      if (scopes.some(scope => left.evidence[scope] && right.evidence[scope] && left.evidence[scope] !== right.evidence[scope])) {
        const note = 'A supplied link conflicts on entity, currency or invoice number.';
        for (const node of [left, right]) if (!node.gaps.includes(note)) node.gaps.push(note);
        return;
      }
      edges.set(idKey(left.node, right.node), {left: left.node, right: right.node, basis});
      if (edges.size > 6000) throw Error('Narrow this review to fewer relationships.');
    }

    for (const [index, row] of rows.entries()) {
      const node = nodes[index], evidence = node.evidence;
      if (node.state !== 'record present') continue;
      if (['payment', 'credit_memo', 'debit_memo', 'statement', 'journal'].includes(row.kind) && evidence.invoice_id)
        link(resolve({kind: 'invoice', id: evidence.invoice_id}), node, preview ? 'Suggested invoice ID' : 'Reviewed invoice ID');
      if (row.kind === 'invoice' && evidence.journal_entry) {
        const journal = resolve({kind: 'journal', id: evidence.journal_entry});
        if (journal?.evidence.invoice_id && journal.evidence.invoice_id !== node.id)
          node.gaps.push('Invoice and journal point to different invoice IDs.');
        else link(node, journal, preview ? 'Suggested journal ID' : 'Reviewed journal ID');
      }
      if (row.kind === 'event' && evidence.original_id)
        link(resolve({kind: 'event', id: evidence.original_id}), node, preview ? 'Suggested original event ID' : 'Reviewed original event ID');
      if (row.kind === 'calculation' && evidence.assignment_id)
        link(resolve({kind: 'policy', id: evidence.assignment_id}), node, preview ? 'Suggested policy assignment ID' : 'Reviewed policy assignment ID');
      if (row.kind === 'aggregate') {
        const members = get(row.raw, 'members');
        const required = ['measure', 'grain', 'period_start', 'period_end', 'basis'].filter(field => !evidence[field]);
        if (required.length) node.gaps.push('Aggregate definition missing ' + required.map(words).join(', ') + '.');
        if (Array.isArray(members) && members.length) {
          if (members.length > 500) throw Error('A rollup can list up to 500 contributor references.');
          const unique = new Set();
          for (const member of members) {
            const target = resolve(member);
            if (!target) node.gaps.push('A contributor reference needs a supported type and unique ID.');
            else if (unique.has(target.node)) node.gaps.push('A contributor is listed more than once.');
            else { unique.add(target.node); link(target, node, 'Supplied contributor reference'); }
          }
          if (get(row.raw, 'members_complete') !== true) node.gaps.push('Confirm contributor completeness for this period and measure.');
        } else if (!evidence.manifest_ref) {
          node.gaps.push('No contributor list or query manifest supplied. The total cannot establish its membership.');
        } else node.gaps.push('Retrieve the query manifest and confirm contributor completeness.');
      }
    }

    if (importedLinks.length > 6000 || lineage.length > 2000) throw Error('Narrow this review to fewer supplied relationships.');
    for (const item of importedLinks) {
      const left = resolve(get(item, 'from')), right = resolve(get(item, 'to'));
      if (left && right) link(left, right, 'Supplied crosswalk');
      else gaps.push('A supplied crosswalk is missing a supported type or unique ID.');
    }
    for (const {from, to} of reviewedLinks) {
      link(nodes[from], nodes[to], 'Reviewer-confirmed relationship');
    }

    const lineCounts = new Map();
    for (const row of lineage) {
      const key = idKey(ref(get(row, 'invoice_id')), ref(get(row, 'invoice_line_id')));
      lineCounts.set(key, (lineCounts.get(key) || 0) + 1);
    }
    for (const row of lineage) {
      const invoiceId = ref(get(row, 'invoice_id'));
      const lineId = ref(get(row, 'invoice_line_id'));
      const calculationId = ref(get(row, 'calculation_id'));
      const invoice = byKey.get(idKey('invoice', invoiceId));
      if (!invoice || invoice.state !== 'record present' || !lineId || !calculationId) continue;
      const lines = get(rows[invoice.node]?.raw, 'lines');
      if (!Array.isArray(lines) || lines.filter(line => ref(get(line, 'id')) === lineId).length !== 1) continue;
      if (lineCounts.get(idKey(invoiceId, lineId)) > 1) {
        const note = 'Multiple crosswalks claim the same invoice line. Confirm the exact version before linking.';
        if (!invoice.gaps.includes(note)) invoice.gaps.push(note);
        continue;
      }
      if (['entity', 'currency'].some(field => ref(get(row, field)) && invoice.evidence[field] &&
          ref(get(row, field)) !== invoice.evidence[field])) {
        invoice.gaps.push('An invoice-line crosswalk conflicts on entity or currency.');
        continue;
      }
      const calculation = resolve({kind: 'calculation', id: calculationId});
      link(calculation, invoice, 'Supplied invoice-line crosswalk');
      const assignment = ref(get(row, 'assignment_id'));
      if (assignment) link(resolve({kind: 'policy', id: assignment}), calculation, 'Supplied policy assignment reference');
      const normalized = get(row, 'normalized_record_ids');
      if (Array.isArray(normalized)) for (const id of normalized.slice(0, 100))
        link(resolve({kind: 'normalized', id}), calculation, 'Supplied selected fact reference');
    }

    const forward = nodes.map(() => []), reverse = nodes.map(() => []);
    for (const {left, right, basis} of edges.values()) {
      forward[left].push({node: right, basis});
      reverse[right].push({node: left, basis});
    }
    function walk(start, graph) {
      const seen = new Set([start]), queue = [{node: start, distance: 0}], result = [];
      for (let index = 0; index < queue.length; index++) {
        const current = queue[index];
        if (current.distance >= 5) continue;
        for (const next of graph[current.node]) {
          if (seen.has(next.node)) continue;
          const step = {...next, distance: current.distance + 1};
          seen.add(next.node);
          result.push(step);
          if (result.length === 30) return result;
          queue.push(step);
        }
      }
      return result;
    }

    const coverage = new Map();
    for (const node of nodes) {
      node.upstream = walk(node.node, reverse);
      node.downstream = walk(node.node, forward);
      const classification = coverage.get(node.type) || {type: node.label, records: 0, record_gaps: 0,
        upstream_gaps: 0, downstream_gaps: 0};
      if (node.state !== 'reference only') {
        classification.records++;
        classification.record_gaps += Number(Boolean(node.gaps.length));
        coverage.set(node.type, classification);
      }
      for (const [index, direction] of ['Upstream', 'Downstream'].entries()) {
        const question = config.expected[node.type][index];
        if (!question) continue;
        const connected = node[direction.toLowerCase()];
        const missing = connected.some(step => step.distance === 1 && nodes[step.node].state === 'reference only');
        const state = missing ? 'Referenced record missing' : connected.length ? 'Confirm evidence' : 'No direct link supplied';
        node.guidance.push({direction, state, ask_for: question});
        if (node.state !== 'reference only' && state !== 'Confirm evidence') classification[direction.toLowerCase() + '_gaps']++;
      }
    }

    return {input_count: fileCount, graph: {entries: nodes, links: edges.size, coverage: [...coverage.values()],
      link_gaps: [...new Set(gaps)]}, invoices: [], coverage: [], unattached: [], duplicate_invoice_ids: [],
      inputs: [{input: 'review', recognized: Object.fromEntries(counts), unmapped_count: counts.get('unmapped') || 0}],
      interactive_import: true, cycle_preview: preview};
  }

  return {parse, records, prepare, fieldNames, candidates, setKind, eventKinds, mapped, build};
}

if (typeof module !== 'undefined') module.exports = createTraceImport;
