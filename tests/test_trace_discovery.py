import io
import unittest
from decimal import Decimal

from scripts import trace_campfire as trace
from scripts import trace_discovery as discovery


class TraceDiscoveryTest(unittest.TestCase):
    def setUp(self):
        with trace.SAMPLE.with_name('unfamiliar-export.json').open() as source:
            self.payload = trace.load(source)

    def test_unknown_nested_record_is_detected_without_echoing_values(self):
        self.assertFalse(trace.known_shape(self.payload))
        result = discovery.discover(self.payload)
        self.assertIn('proposed', result['status'])
        self.assertEqual(['batch', 'payload', 0, 'billingRecord'], result['candidates'][0]['record_path'])
        self.assertEqual('invoice', result['candidates'][0]['proposed_kind'])
        self.assertEqual(['totals', 'grossAmount'], result['draft_mapping']['mappings'][0]['fields']['total_amount'])
        self.assertNotIn('bill-redacted-A', str(result))

    def test_review_is_required_and_mapping_preserves_missing_evidence(self):
        mapping = discovery.discover(self.payload)['draft_mapping']
        with self.assertRaisesRegex(ValueError, 'reviewed to true'):
            discovery.apply_mapping(self.payload, mapping, trace.GROUPS)
        mapping['reviewed'] = True
        reviewed = discovery.apply_mapping(self.payload, mapping, trace.GROUPS)
        report = trace.inspect(reviewed)
        self.assertEqual('bill-redacted-A', report['anchor']['id'])
        self.assertEqual('line-redacted-A', report['workflow'][2]['evidence']['line_id'])
        self.assertEqual('missing', report['workflow'][2]['status'])
        self.assertEqual(Decimal('35.00'), report['invoice_balance']['reported_balance'])
        self.assertEqual('insufficient evidence', report['invoice_balance']['status'])

    def test_two_plausible_balance_fields_are_not_decided_for_reviewer(self):
        path = ['batch', 'payload', 0, 'billingRecord']
        discovery.at(self.payload, path)['openBalance'] = '36.00'
        outcome = discovery.discover(self.payload, record_path=path)
        fields = outcome['candidates'][0]['options'][0]['fields']
        self.assertEqual(2, len(fields['amount_due']))
        self.assertNotIn('amount_due', outcome['draft_mapping']['mappings'][0]['fields'])

    def test_opaque_labels_return_shape_inventory_without_a_guess(self):
        result = discovery.discover({'a': 'sensitive-alias', 'b': 3500})
        self.assertEqual([], result['candidates'])
        self.assertEqual([{'path': ['a'], 'shape': 'text'}, {'path': ['b'], 'shape': 'number'}],
                         result['shape_inventory'][0]['fields'])
        self.assertNotIn('sensitive-alias', discovery.markdown(result))

    def test_csv_can_propose_fields_without_an_explicit_column_map(self):
        rows = trace.load(io.StringIO('Invoice ID,Bill Number,Invoice Total,Amount Due,Currency Code\nA,001,25.00,15.00,USD\n'), is_csv=True)
        result = discovery.discover(rows)
        self.assertEqual('invoice', result['candidates'][0]['proposed_kind'])
        self.assertEqual(['Invoice ID'], result['draft_mapping']['mappings'][0]['fields']['id'])

    def test_reviewed_path_drift_is_reported_instead_of_dropping_a_field(self):
        mapping = discovery.discover(self.payload)['draft_mapping']
        mapping['reviewed'] = True
        mapping['mappings'][0]['fields']['amount_due'] = ['amountMoved']
        with self.assertRaisesRegex(ValueError, 'Reviewed source path is missing'):
            discovery.apply_mapping(self.payload, mapping, trace.GROUPS)
