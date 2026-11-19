'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {plan} = require('../scripts/trace_workflow_cycle.js');
const {observe, review, gapRows, gapCsv} = require('../scripts/trace_workflow_dimensions.js');

function point(type, evidence = {}, links = {}) {
  return {type, evidence, id: 'synthetic-record', upstream: [], downstream: [], ...links};
}

test('an unexplained rollup leaves the amount basis and cycle branches open', () => {
  const cycle = plan(point('aggregate', {total_amount: '100.00', currency: 'USD'}), []);
  assert.match(cycle.context, /basis is unclear/);
  assert.ok(cycle.identityFields.includes('Basis · unknown'));
  assert.ok(cycle.identityFields.includes('Reported total · 100.00 USD'));
  assert.ok(cycle.upstream.every(card => card.state === 'conditional' && !card.actual.length));
  assert.ok(cycle.downstream.every(card => card.state === 'conditional'));
});

test('invoice rollups suggest issued invoices upstream and leave consumers conditional', () => {
  const cycle = plan(point('aggregate', {measure: 'Original invoice total'}), []);
  assert.equal(cycle.upstream.find(card => card.title === 'Savvy invoice').state, 'expected');
  assert.ok(!cycle.downstream.some(card => card.title === 'Savvy invoice'));
  assert.equal(cycle.downstream.find(card => card.title === 'Campfire accounting').state, 'conditional');
});

test('a rollup of invoice payments suggests cash activity', () => {
  const cycle = plan(point('aggregate', {measure: 'Invoice payments'}), []);
  assert.match(cycle.context, /cash or accounting activity/);
  assert.equal(cycle.upstream.find(card => card.title === 'Cash and application').state, 'conditional');
});

test('supplied invoice and unresolved journal show distinct evidence states', () => {
  const cycle = plan(point('aggregate', {}, {upstream: [{node: 0}], downstream: [{node: 1}]}), [
    {type: 'invoice', state: 'record present'}, {type: 'journal', state: 'reference only'},
  ]);
  assert.equal(cycle.upstream.find(card => card.title === 'Savvy invoice').state, 'linked');
  assert.equal(cycle.downstream.find(card => card.title === 'Campfire accounting').state, 'reference');
});

test('payout requests leave settlement conditional even when an ID is present', () => {
  const cycle = plan(point('event', {event_type: 'payout_request'}), []);
  assert.match(cycle.context, /confirmed cash movement/);
  assert.equal(cycle.upstream.find(card => card.title === 'Earnings and payable').state, 'expected');
  assert.equal(cycle.downstream.find(card => card.title === 'Payout and settlement').state, 'conditional');
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
