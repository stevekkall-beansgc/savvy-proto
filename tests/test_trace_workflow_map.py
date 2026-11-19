import unittest
from decimal import Decimal

from scripts import trace_campfire as trace, trace_discovery
from scripts import trace_workflow_map as workflow


def entry(report, identity):
    return next(row for row in report['graph']['entries'] if row['id'] == identity)


def linked_ids(report, row, direction):
    return [report['graph']['entries'][link['node']]['id'] for link in row[direction]]


class WorkflowMapTest(unittest.TestCase):
    def test_rollup_trace_goes_both_ways_and_reports_reference_only(self):
        with workflow.SAMPLE.open() as source:
            bundle = trace.load(source)
        report = workflow.build([bundle])
        rollup = entry(report, 'billed-rollup-oct')
        self.assertIn('custody-delivery-A', linked_ids(report, rollup, 'upstream'))
        self.assertIn('invoice-harbor', linked_ids(report, rollup, 'upstream'))
        self.assertEqual(['monthly-accounting-review-unprovided'], linked_ids(report, rollup, 'downstream'))
        self.assertEqual('reference only', entry(report, 'monthly-accounting-review-unprovided')['state'])
        self.assertEqual('Referenced record missing', rollup['guidance'][1]['state'])
        aggregate = next(row for row in report['graph']['coverage'] if row['type'] == 'Billing aggregate')
        self.assertEqual((2, 1, 2), (aggregate['records'], aggregate['upstream_gaps'], aggregate['downstream_gaps']))
        harbor = next(row for row in report['invoices'] if row['invoice_id'] == 'invoice-harbor')
        cash = next(row for row in harbor['stages'] if row['id'] == 'cash')
        self.assertEqual('tied out', cash['state'])
        self.assertEqual(Decimal('35.00'), cash['evidence'][0]['computed_balance'])

    def test_equal_totals_never_establish_membership(self):
        report = workflow.build([{'kind':'aggregate','id':'rollup','total_amount':'100.00'},
                                 {'kind':'invoice','id':'inv','total_amount':'100.00'}])
        rollup = entry(report, 'rollup')
        self.assertEqual([], rollup['upstream'])
        self.assertTrue(any('cannot establish its membership' in gap for gap in rollup['gaps']))

    def test_unknown_export_remains_discovery_until_promotion(self):
        raw = {'summary':{'rollupId':'rolled-up', 'metricName':'gross billing', 'aggregationGrain':'team/month',
                          'grossAmount':'250.00', 'currencyCode':'USD'}}
        before = workflow.build([raw])
        self.assertEqual('unmapped', before['graph']['entries'][0]['type'])
        self.assertEqual('aggregate', before['inputs'][0]['discovery'][0]['proposed_kind'])
        draft = trace_discovery.discover(raw, 'aggregate')['draft_mapping']
        draft['reviewed'] = True
        seen = trace_discovery.apply_mapping(raw, draft, workflow.trace_entry_graph.GRAPH_GROUPS)
        after = workflow.build([seen])
        self.assertEqual('aggregate', entry(after, 'rolled-up')['type'])
        self.assertEqual('250.00', entry(after, 'rolled-up')['evidence']['total_amount'])
        self.assertEqual('gross billing', entry(after, 'rolled-up')['evidence']['measure'])
        self.assertEqual(0, after['graph']['links'])

    def test_any_entry_point_in_a_cross_file_trace(self):
        source = {'kind':'source', 'id':'delivery-A'}
        packet = {'entries':[{'kind':'normalized','id':'fact-A'}, {'kind':'calculation','id':'calc-A'}], 'links':[
            {'from':{'kind':'source','id':'delivery-A'},'to':{'kind':'normalized','id':'fact-A'}},
            {'from':{'kind':'normalized','id':'fact-A'},'to':{'kind':'calculation','id':'calc-A'}}]}
        result = workflow.build([source, packet])
        self.assertEqual(['delivery-A', 'fact-A', 'calc-A'], [row['id'] for row in result['graph']['entries']])
        self.assertEqual(['fact-A', 'calc-A'], linked_ids(result, entry(result, 'delivery-A'), 'downstream'))
        self.assertEqual(['fact-A', 'delivery-A'], linked_ids(result, entry(result, 'calc-A'), 'upstream'))

    def test_scope_conflicts_and_duplicate_invoice_ids_stay_open(self):
        rollup = {'kind':'aggregate','id':'rollup','entity':'A','members':[{'kind':'invoice','id':'invoice'}]}
        invoice = {'kind':'invoice','id':'invoice','entity':'B'}
        result = workflow.build([rollup, invoice])
        self.assertFalse(entry(result, 'rollup')['upstream'])
        self.assertIn('conflicting entity', ' '.join(entry(result, 'rollup')['gaps']))
        conflict = workflow.build([rollup, invoice, {**invoice,'entity':'A'}])
        self.assertEqual(['invoice'], conflict['duplicate_invoice_ids'])
        self.assertTrue(conflict['graph']['link_gaps'])
        self.assertFalse(entry(conflict, 'rollup')['upstream'])

    def test_multiple_sources_do_not_inherit_blanket_reconciliation(self):
        with trace.SAMPLE.open() as source:
            bundle = trace.load(source)
        result = workflow.build([bundle, {'kind':'source','id':'additional'}])
        cash = next(row for row in result['invoices'][0]['stages'] if row['id'] == 'cash')
        self.assertEqual('insufficient evidence', cash['evidence'][0]['status'])

    def test_competing_line_crosswalks_do_not_establish_lineage(self):
        invoice = {'kind': 'invoice', 'id': 'inv', 'lines': [{'id': 'line'}]}
        line = {'invoice_id': 'inv', 'invoice_line_id': 'line', 'calculation_id': 'first'}
        competing_line = {**line, 'calculation_id': 'second'}
        result = workflow.build([invoice, {'kind': 'source', 'id': 'source-A'}, {'lineage': [line, competing_line]}])
        row = entry(result, 'inv')
        self.assertEqual([], row['upstream'])
        self.assertIn('Multiple crosswalks', ' '.join(row['gaps']))

    def test_single_record_uses_its_fields_and_excludes_wrapper_evidence(self):
        invoice = {
            'kind': 'invoice', 'id': 'inv', 'currency': 'USD', 'total_amount': '125.00',
            'journal_entry': {'id': 'journal-A'}, 'lines': [{'id': 'line-A'}],
        }
        bundle = {
            'entries': [invoice],
            'links': [{'from': {'kind': 'invoice', 'id': 'inv'}, 'to': {'kind': 'payment', 'id': 'outside'}}],
            'lineage': [{'invoice_id': 'inv', 'invoice_line_id': 'line-A', 'calculation_id': 'outside-calc'}],
        }
        result = workflow.build([bundle])
        self.assertEqual({'ignored_rows': 2}, result['single_record'])
        self.assertEqual(['inv', 'journal-A'], [row['id'] for row in result['graph']['entries']])
        journal = entry(result, 'journal-A')
        self.assertEqual('reference only', journal['state'])
        self.assertEqual({}, journal['evidence'])
        self.assertEqual('journal_entry.id', journal['reference_from']['field'])
        self.assertEqual(1, sum(row['records'] for row in result['graph']['coverage']))

    def test_line_variance_is_a_gap_at_the_calculation_stage(self):
        with trace.SAMPLE.open() as source:
            bundle = trace.load(source)
        bundle['lineage'][0]['expected_line_amount'] = '250.01'
        result = workflow.build([bundle])
        gold = next(row for row in result['invoices'][0]['stages'] if row['id'] == 'gold')
        self.assertEqual('variance', gold['state'])
        self.assertIn('1 line amounts differ', ' '.join(gold['gaps']))
