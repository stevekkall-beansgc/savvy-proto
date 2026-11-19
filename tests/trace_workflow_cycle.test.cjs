'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {creationFlow, rollupContributor} = require('../scripts/trace_workflow_cycle.js');
const {observe, review, gapRows, gapCsv} = require('../scripts/trace_workflow_dimensions.js');
const {capture, model} = require('../scripts/trace_workflow_previews.js');
const profiles = require('../scripts/trace_record_profiles.json');

function point(type, evidence = {}, links = {}) {
  return {type, evidence, id: 'synthetic-record', upstream: [], downstream: [], ...links};
}

const mainSteps = flow => flow.process[0].steps;
const stepKeys = steps => steps.map(step => step.key);

test('an unexplained rollup displays possible inputs outside the creation sequence', () => {
  const flow = creationFlow(point('aggregate', {total_amount:'100.00', currency:'USD'}), []);
  const [rollup, report] = mainSteps(flow);
  assert.match(flow.context, /basis is unclear/);
  assert.ok(flow.identityFields.includes('Reported total · 100.00 USD'));
  assert.deepEqual(stepKeys(mainSteps(flow)), ['aggregate','reporting']);
  assert.match(rollup.inputs.label, /Possible inputs/);
  assert.deepEqual(stepKeys(rollup.inputs.steps), ['calculation','invoice','payment']);
  assert.equal(report.state, 'expected');
});

test('invoice rollups put issue before aggregation and feed policy into the calculation separately', () => {
  const flow = creationFlow(point('aggregate', {measure:'Original invoice total'}), []);
  const steps = mainSteps(flow);
  assert.deepEqual(stepKeys(steps), ['source','normalized','calculation','invoice','aggregate','reporting']);
  assert.deepEqual(stepKeys(steps[2].inputs.steps), ['policy']);
  assert.equal(steps[3].state, 'expected');
  assert.equal(steps[4].isAnchor, true);
  assert.equal(steps[4].action, 'Sum issued invoices');
});

test('cash amounts roll up applied payments after invoice issuance', () => {
  const flow = creationFlow(point('aggregate', {measure:'Invoice payments'}), []);
  assert.deepEqual(stepKeys(mainSteps(flow)).slice(3), ['invoice','payment','aggregate','reporting']);
  assert.equal(mainSteps(flow)[4].action, 'Apply confirmed cash');
});

test('journal references retain partial status at the posting step without filling the missing package', () => {
  const flow = creationFlow(point('invoice', {}, {downstream:[{node:0}]}),
    [{type:'journal', state:'reference only'}], {singleRecord:true});
  const steps = mainSteps(flow);
  assert.deepEqual(stepKeys(steps).slice(3), ['invoice','package','journal','reporting']);
  assert.equal(steps[4].state, 'expected');
  assert.equal(steps[5].state, 'reference');
});

test('payout requests feed settlement alongside the payable produced by the engine', () => {
  const flow = creationFlow(point('event', {event_type:'payout_request'}), []);
  const steps = mainSteps(flow);
  assert.deepEqual(stepKeys(steps), ['source','normalized','calculation','payable','payout']);
  assert.equal(steps[4].inputs.steps[0].isAnchor, true);
  assert.match(flow.context, /confirmation that cash moved/);
});

test('the source path branches into the client and earnings workflows after the calculation', () => {
  const {process} = creationFlow(point('source'), []);
  assert.deepEqual(process.map(track => stepKeys(track.steps)), [
    ['source','normalized','calculation'], ['invoice','statement'], ['payable','payout'],
  ]);
  assert.deepEqual(process.slice(1).map(track => track.from), ['Fee calculation','Fee calculation']);
});

test('all supported starting records appear once in their process', () => {
  const allSteps = steps => steps.flatMap(step => [step, ...allSteps(step.inputs?.steps || [])]);
  const kinds = [...Object.keys(profiles.fields), 'unmapped'];
  for (const kind of kinds) {
    const {process} = creationFlow(point(kind), []);
    const anchors = allSteps(process.flatMap(track => track.steps)).filter(step => step.isAnchor);
    assert.equal(anchors.length, 1, kind);
    assert.ok(anchors[0].kinds.includes(kind), kind);
  }
});

test('journal dimensions distinguish sample visibility from prototype coverage', () => {
  const journal = {posting_period:'2026-11', lines:[
    {amount_minor: 80, glAccount:{code:'ledger-A'}, dimensions:{customerId:'customer-A', costCenter:'center-A', desk:'desk-A'}},
    {amount_minor: -80, account_id:'ambiguous-A'},
  ]};
  const record = dimensionPoint(0, 'journal', journal);
  const rows = new Map(review(record, [record]).map(row => [row.dimension, row]));
  assert.deepEqual(rows.get('General ledger account').fields.map(field => field.path), ['lines[].glAccount.code']);
  assert.equal(rows.get('General ledger account').status, 'missing');
  assert.equal(rows.get('Customer').status, 'dropped');
  assert.equal(rows.get('Posting period').status, 'carried');
  assert.equal(rows.get('Unreviewed field · desk').status, 'review');
  assert.equal(rows.get('Account ID meaning').status, 'review');
  assert.deepEqual(rows.get('Advisor or broker').fields, []);
  assert.ok(![...rows.values()].flatMap(row => row.fields).some(field => field.path.endsWith('amount_minor')));
});

function dimensionPoint(node, type, values, options = {}) {
  return point(type, {}, {node, id:type + '-' + node, label:type, observed_fields:observe(values),
    state:'record present', ...options});
}

test('a linked calculation flags only the handoff where a dimension stops appearing', () => {
  const source = dimensionPoint(0, 'source', {account_id:'a', dimensions:{partnerChannel:'demo'}},
    {downstream:[{node:1, distance:1}, {node:2, distance:2}]});
  const silver = dimensionPoint(1, 'normalized', {account_id:'a', dimensions:{partnerChannel:'demo'}},
    {upstream:[{node:0, distance:1}], downstream:[{node:2, distance:1}]});
  const gold = dimensionPoint(2, 'calculation', {account_id:'a'},
    {upstream:[{node:1, distance:1}, {node:0, distance:2}]});
  const rows = review(gold, [source, silver, gold]);
  const partner = rows.find(row => row.dimension === 'Unreviewed field · partner channel');
  assert.equal(partner.fields.length, 2);
  assert.equal(partner.handoffs.length, 1);
  assert.equal(partner.handoffs[0].before, 'normalized · normalized-1');
  assert.equal(partner.handoffs[0].after, 'calculation · calculation-2');
  assert.equal(rows.find(row => row.dimension === 'Custodial account').handoffs.length, 0);
});

test('report headings describe expectations and do not prove a populated field or a missing record', () => {
  const invoice = dimensionPoint(0, 'invoice', {customer_id:'a'}, {downstream:[{node:1, distance:1}]});
  const report = dimensionPoint(1, 'report', {}, {
    declared_dimensions:['Billing Product', 'Cost Center', 'Amount'],
    upstream:[{node:0, distance:1}],
  });
  const rows = review(report, [invoice, report]);
  assert.equal(rows.find(row => row.dimension === 'Cost center').fields[0].declared, true);
  assert.equal(rows.find(row => row.dimension === 'Customer').handoffs.length, 0);
  assert.ok(!rows.some(row => row.dimension.includes('amount')));
});

test('the gap list retains coverage and verification as separate rows', () => {
  const invoice = dimensionPoint(0, 'invoice', {customer_id:'customer-value', posting_period:'2026-11'},
    {downstream:[{node:1, distance:1}]});
  const posting = dimensionPoint(1, 'accounting_package', {posting_period:'2026-11'}, {upstream:[{node:0,distance:1}]});
  const rows = gapRows(invoice, review(invoice, [invoice, posting]));
  const customer = rows.filter(row => row[1] === 'Customer');
  assert.deepEqual(customer.map(row => row[2]), ['Prototype handoff gap', 'Possible loss in supplied handoff']);
  assert.deepEqual(customer[1].slice(7, 9), ['invoice · invoice-0', 'accounting_package · accounting_package-1']);
  assert.ok(rows.every(row => row.length === 11 && row.at(-1) === 'Open'));
  assert.ok(!rows.some(row => row[1] === 'Posting period'));
  assert.doesNotMatch(gapCsv(rows), /customer-value/);
});

test('CSV escapes quotes, multiline text, and spreadsheet formulas', () => {
  const text = gapCsv([[' =demo', '+demo', '-demo', '@demo', '\ttext', 'a,"b"\nc']]);
  assert.ok(text.endsWith(`"' =demo","'+demo","'-demo","'@demo","'\ttext","a,""b""\nc"\r\n`));
});

test('every profile renders expected fields without inventing values', () => {
  for (const kind of Object.keys(profiles.fields)) {
    const view = model(kind, undefined, profiles);
    assert.equal(view.rows[0].field, 'Record ID');
    assert.ok(view.rows.every(row => row.status === 'To confirm' && row.value === undefined), kind);
    assert.ok(view.sections.every(section => section.rows.length === 0), kind);
  }
});

test('record previews distinguish reference IDs from actual line values', () => {
  const reference = model('journal', {id:'journal-1', state:'reference only', evidence:{}}, profiles);
  assert.deepEqual(reference.rows[0], {field:'Record ID', value:'journal-1', status:'Reference'});
  assert.ok(reference.rows.slice(1).every(row => row.value === undefined));
  const raw = {posting_period:'2026-11', lines:[{id:'line-1', debit_minor:'999999999999999', credit_minor:0, cost_center:'operations'}]};
  const actual = model('journal', {id:'journal-2', state:'record present', evidence:{}, preview:capture(raw,'journal',profiles)}, profiles);
  assert.equal(actual.rows.find(row => row.field === 'Posting period').value, '2026-11');
  assert.deepEqual(actual.sections[0].rows, [['line-1','999999999999999','0','operations']]);
  assert.equal(actual.rows.find(row => row.field === 'Currency').status, 'Not supplied');
});

test('single-record invoice rollups illustrate only fields supported by the rollup', () => {
  const fieldValues = {measure:'Original invoice total', basis:'Issued originals', grain:'Entity / month',
    currency:'USD', period_start:'2026-10-01', period_end:'2026-10-31', total_amount:'1319.18'};
  const partial = point('aggregate', fieldValues);
  const row = rollupContributor(partial);
  assert.equal(row.currency, 'USD');
  assert.equal(row.start, '2026-10-01');
  assert.equal(row.amount, null);
  assert.equal(mainSteps(creationFlow(partial, []))[3].example, null);
  assert.equal(mainSteps(creationFlow(partial, [], {singleRecord:true}))[3].state, 'illustration');

  function withContributors(count, members) {
    const raw = {...fieldValues, contributor_count:count, ...(members ? {members} : {})};
    return {...partial, preview:capture(raw,'aggregate',profiles)};
  }
  assert.equal(rollupContributor(withContributors(1)).amount, '1319.18');
  assert.equal(rollupContributor(withContributors(2)).amount, null);
  assert.equal(rollupContributor(withContributors(1,[{kind:'invoice'},{kind:'invoice'}])).amount, null);
  assert.equal(rollupContributor({...partial, evidence:{...fieldValues,measure:'Cash collected on invoices'}}), null);
});
