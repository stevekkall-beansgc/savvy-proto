#!/usr/bin/env python3
"""Compare hand-specified commercial examples with an executed evidence export.

This uses only the Python standard library and no Savvy engine code. Inputs
below are the sample contract and independently supplied payment assumptions.
The export is used only as the actual side of the comparison.
"""
import argparse
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def cents(value):
    return int(value.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP) * 100)


def expected():
    advisor_gross = [cents(Decimal(balance) * Decimal('0.012') * 31 / 365 + 50)
                     for balance in (1_000_000, 1_200_000, 1_400_000)]
    alder = advisor_gross[0]
    alder_cash = 53459
    book_share = sum(cents(Decimal(bill) / 100 * Decimal('0.8')) for bill in advisor_gross)
    advisor_payable = book_share + 500000 + 100000 - 20000 - 100000 - 10000
    ria_original = min(10000 + 6 * 3000, 25000)
    ria_net = min(10000 + 2 * 3000, 25000)
    ria_cash = 12500
    refund_requested, refund_confirmed = 5000, 2000

    def case(net, cash, entitlement, payout):
        return {
            'billing': {'assessed_minor': net, 'applied_minor': cash, 'outstanding_minor': net - cash},
            'credit': {'requested_minor': refund_requested, 'confirmed_refund_minor': refund_confirmed,
                       'credit_balance_minor': refund_requested - refund_confirmed},
            'earnings': {'assessed_minor': entitlement, 'applied_minor': payout, 'outstanding_minor': entitlement - payout},
            'accounting': {'reported_ar_minor': net - cash},
        }

    checks = {'advisor': case(alder, alder_cash, advisor_payable, 100000),
              'ria': case(ria_net, ria_cash, 5000, 2000)}
    formulas = {'advisor_book_original_minor': sum(advisor_gross),
                'ria_correction_minor': ria_original - ria_net}
    return checks, formulas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', nargs='?', type=Path, default=ROOT / 'docs/architecture/lifecycle-run.json')
    args = parser.parse_args()
    payload = json.loads(args.export.read_text())
    assert payload['synthetic'] and payload['schema'] == 'billing-lifecycle-proof/v1'
    actual = {case['case_id']: case for case in payload['cases']}
    checks, formulas = expected()
    assert set(actual) == set(checks)
    count = 0
    for case, sections in checks.items():
        for section, fields in sections.items():
            for field, value in fields.items():
                observed = actual[case][section][field]
                assert observed == value, f'{case}/{section}/{field}: expected {value}, saw {observed}'
                count += 1
    print(json.dumps({'passed': count, 'supporting_expected_values_minor': formulas,
                      'finance_signoff': 'pending'}))


if __name__ == '__main__':
    main()
