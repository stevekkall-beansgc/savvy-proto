# Savvy Finance review

This is a sign-off worksheet for synthetic examples. Amounts are USD. The
expected figures below come from the stated inputs and arithmetic. Ask Finance
to confirm the commercial assumptions, rounding, cash attribution and policy
for recognition before approving their use beyond the prototype.

| Case | Inputs and independent working | Expected |
| --- | --- | --- |
| Alder household, October | $1m eligible for 31 days at 1.2% annual, actual/365, plus $50 planning | $1,069.18 billed |
| Advisor book, October | Alder $1,069.18 + Birch $1,273.01 + Cedar $1,476.85; add $106.92 debit, subtract $106.92 credit for the Alder reallocation | $3,819.04 net billed |
| Alder cash | $1,069.18 net bill less $534.59 confirmed applied cash | $534.59 outstanding |
| Harbor RIA, October | Original $100 + 6 × $30 capped at $250. Revised $100 + 2 × $30 = $160. Reported custody income is separate. | $90 credit; $160 net billed |
| Harbor cash | $160 net bill less $125 confirmed applied cash | $35 outstanding |
| September refunds | $50 excess credit in each example, $20 confirmed refunded | $30 credit left per example |
| Advisor earnings | 80% of the issued fee amounts rounded per assessment, plus $5,000 salary and $1,000 bonus, less $200 expenses, $1,000 advance and $100 loan repayment | $7,755.23 approved; $1,000 applied; $6,755.23 owed |
| Harbor incentive | $50 approved incentive less $20 confirmed payout | $30 owed |
| Prepaid fee termination | $2m prior-period balance × 1% ÷ 12 = $1,666.67 assessed. 15 of 30 service days, applied before rounding, yields $833.33. | $833.34 credit; confirmed refund clears it |

Run `python3 scripts/finance_acceptance.py` to compare both retained October
chains and the earlier refund/earnings figures with a standard-library
calculation. Pass a current read-only lifecycle export as the argument to compare
against a running build. The Rails lifecycle suite checks the separate prepaid
termination example through invoice, correction and confirmed refund. The
workbook's paid and recognition evidence can have different dates from the bill.

For accounting, verify the supplied mock schedules and journal IDs in Finance.
The October example supplies the full billed amount as recognized and zero
deferred. Ask whether that treatment and its service dates are right separately
from whether cash was matched correctly. Confirm whether Campfire should own
recognition policy selection and the mapping to actual journal references.

| Decision | Record during review |
| --- | --- |
| Billing methods and rounding | Accepted, revisions requested, or follow-up owner |
| Refund and correction treatment | Accepted, revisions requested, or follow-up owner |
| Campfire recognition and cash handoff | Accepted, revisions requested, or follow-up owner |

Savvy Finance sign-off remains pending.
