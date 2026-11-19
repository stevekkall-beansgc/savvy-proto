import copy
import io
import unittest
from decimal import Decimal

from scripts import trace_campfire as trace


class CampfireTraceTest(unittest.TestCase):
    def setUp(self):
        with trace.SAMPLE.open() as source:
            self.sample = trace.load(source)

    def test_journal_to_source_gap_and_exact_native_balance(self):
        with trace.PROTOTYPE.open() as source:
            report = trace.inspect(self.sample, prototype=trace.load(source))
        self.assertEqual('journal', report['anchor']['type'])
        self.assertEqual('matches', report['invoice_balance']['status'])
        self.assertEqual(Decimal('35.00'), report['invoice_balance']['computed_balance'])
        self.assertEqual(Decimal('0.00'), report['prototype']['net_billed_variance'])
        policy = report['workflow'][2]
        self.assertEqual('partial crosswalk', policy['status'])
        self.assertIn('source_record_ids', policy['evidence']['missing'])

    def test_standalone_objects_do_not_infer_relationships_or_zero_cash(self):
        invoice = self.sample['invoices'][0]
        report = trace.inspect({'results': [invoice]})
        self.assertEqual('insufficient evidence', report['invoice_balance']['status'])
        self.assertEqual('missing', report['workflow'][2]['status'])
        report = trace.inspect(self.sample['payments'][0] | {'payment_type': 'OTHER'})
        self.assertEqual('reference only', report['workflow'][0]['status'])
        self.assertNotIn('invoice_balance', report)

    def test_matching_invoice_ids_with_conflicting_scope_do_not_join(self):
        self.sample['journals'][0]['entity'] = 'other-entity'
        report = trace.inspect(self.sample)
        self.assertEqual('reference only', report['workflow'][0]['status'])
        self.assertNotIn('invoice_balance', report)

    def test_statement_requires_the_exact_line_link(self):
        self.sample['statements'][0]['invoice_line_id'] = 'unknown-line'
        report = trace.inspect(self.sample)
        self.assertEqual('observed', report['workflow'][1]['status'])
        self.assertEqual([], report['workflow'][1]['evidence']['statement_linked_lines'])

    def test_incomplete_or_ambiguous_payments_do_not_reconcile(self):
        for change in ('cross_currency', 'duplicate', 'unconfirmed', 'credit_memo'):
            with self.subTest(change=change):
                bundle = copy.deepcopy(self.sample)
                payment = bundle['payments'][0]
                if change == 'cross_currency': payment['currency'] = 'EUR'
                elif change == 'duplicate': bundle['payments'].append(dict(payment))
                elif change == 'unconfirmed': payment.pop('cash_confirmation_id')
                else: payment['payment_type'] = 'CREDIT_MEMO'
                result = trace.inspect(bundle)['invoice_balance']
                self.assertEqual('insufficient evidence', result['status'])
                self.assertNotIn('computed_balance', result)

    def test_void_date_and_one_cent_variance_are_preserved(self):
        self.sample['as_of'] = '2026-11-21'
        self.sample['payments'][0]['voided_date'] = '2026-11-20'
        self.sample['invoices'][0]['amount_due'] = '160.01'
        result = trace.inspect(self.sample)['invoice_balance']
        self.assertEqual('variance', result['status'])
        self.assertEqual(Decimal('0.01'), result['observed_less_computed'])

    def test_duplicate_json_fields_fail_closed(self):
        with self.assertRaisesRegex(ValueError, 'duplicate field'):
            trace.load(io.StringIO('{"id": 1, "id": 2}'))

    def test_csv_mapping_keeps_explicit_invoice_identity(self):
        rows = trace.load(io.StringIO('Invoice ID,Number,Total,Currency\nA,001,25.00,USD\nB,002,75.00,USD\n'),
                          is_csv=True, columns=['id=Invoice ID', 'invoice_number=Number',
                                                'total_amount=Total', 'currency=Currency'])
        report = trace.inspect(rows, kind='invoice', identifier='B')
        self.assertEqual('002', report['workflow'][0]['evidence']['invoice_number'])
        self.assertEqual(Decimal('75.00'), report['invoice_balance']['original_invoice_total'])


if __name__ == '__main__':
    unittest.main()
