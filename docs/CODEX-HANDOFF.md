# Advisor payout prototype: development handoff

> Continuation note (13 November 2026): the local build has resumed. See [current implementation status](CONTINUATION-STATUS.md) and [validation](VALIDATION-CONTINUATION.md). Planning and earlier prototype descriptions below are historical; publication remains paused.

## Outcome and current status

The current deliverable is a runnable, synthetic advisor-payout workbench with
a pure Python calculation engine, a local interactive interface, an offline
Campfire-shaped adapter, reproducible result snapshots and research notes.
Its purpose is to make the financial rules and product workflow concrete before
adapting the model to an employer's staging environment.

This independent standalone working copy remains a prototype. Read
[EVIDENCE-AND-SCOPE.md](EVIDENCE-AND-SCOPE.md) and the README first; they separate
what is known from owner-requested capabilities and unsupported assumptions.
The earlier forecast and the separate commercial reporting experiment do not
implement the policy hierarchy, bidirectional prepurchase or guarantees discussed
later. The Site record is private and unpublished. Do not publish during the
owner's existing pause.

## Reproduce the current artifact

From the experiment root, with Python 3.11+:

```sh
python3 -m unittest discover -s tests -v
python3 -m advisor_payout
```

The local app is at `http://127.0.0.1:8766`. It uses standard-library runtime
components only and needs no credentials or external service. Do not expose the
demonstration server as a production service.

The preview builder, owned by the integration lane, is run with:

```sh
python3 build_preview.py
```

It produces `artifacts/advisor-payout-preview.html`. That file contains exact
Python results for the supported advisor/preset combinations. Custom sliders
belong to the live local server; the offline file does not substitute JavaScript
approximations for authoritative calculations.

Before carrying a result forward, read the final `docs/VALIDATION.md` if present
and distinguish passed, failed and unrun checks. The adapter handoff independently
executed 17 passing focused tests. Final HTTP, complete-suite, offline-preview
and browser evidence is recorded by the integration owner. Do not turn an absent
report into an assumed pass.

## What is implemented

- Three fictional advisor profiles: `advisor-alex`, `advisor-jordan`, and
  `advisor-taylor`.
- Daily observed billable AUM, separate market movement and client flows,
  effective-dated revenue share, pre/post-share costs and capped loan repayment.
- Integer financial calculations with explicit rounding and reconciled daily
  display amounts. Observed history is unchanged by future scenarios.
- Baseline, market/flow and collection scenarios, an explainable payout
  waterfall, assumptions, source notes and JSON snapshot export.
- Loopback HTTP handlers with bounded inputs and an explicit static asset
  allowlist.
- A synthetic Campfire-shaped invoice/payment snapshot, invoice/client/advisor
  mapping checks, stable-record deduplication, retained source versions and
  payment-void handling.
- A GET-only request *plan* for documented Campfire reads. The plan never makes
  a request or sets the email-triggering invoice `download` parameter.
- Primary-source research and exact Legume Labs source-version provenance.

The current supported financial convention is daily closing billable assets,
ACT/365, monthly arrears. This convention was chosen for the demonstration; it
has not been confirmed against an actual advisor agreement.

## Ownership boundaries

| Layer | Owns | Must not infer |
| --- | --- | --- |
| `engine.py` | Financial rules and scenario calculation | ERP settlement, authorization, missing commercial terms |
| `fixtures.py` | Explicit synthetic inputs | Real client or employer facts |
| `campfire.py` | Supplied source normalization and evidence comparison | Unknown payment types as cash, invoice void as refund, advisor identity from names |
| `server.py` | Local transport and result envelopes | Pricing outside the engine or external writes |
| `web/` | Presentation, controls and exact result rendering | Separate authoritative money arithmetic |
| Preview builder | Frozen snapshots from the same Python calculation path | Arbitrary offline scenario computation |

Core design assets are directly reused. The Finance Library and Bean Counter
inform design choices. No Bean Counter runtime adapter has been implemented or
validated. Exact references are in `LEGUME-REUSE.md`.

## Next bounded milestone

**Recommended next result:** agree one representative advisor contract and one
historical closed period, express their rules as a versioned input contract, and
reconcile the prototype against the finance owner's accepted worksheet using
anonymized or explicitly authorized staging data.

Acceptance should be concrete:

1. Every input has an identified source, effective date, entity, currency and
   owner. Missing inputs fail or visibly withhold the affected amount.
2. Gross fees, advisor split, each deduction, debt repayment and resulting cash
   reproduce the agreed reference calculation, including its rounding boundary.
3. The daily asset history reconciles opening balances, flows, market changes
   and closing billable balances without double counting.
4. Actuals, projections, service periods, cutoff dates and collection horizons
   remain separately labeled.
5. ERP records map to the intended advisor/client/contract scope. Replayed
   observations do not duplicate totals; later updates retain source history.
6. An explicit finance review resolves any discrepancy before this is treated
   as a usable estimate for real advisors.

Stop this milestone at an inspectable reconciliation report and the smallest
necessary code change. A successful comparison does not authorize an ERP write,
production deployment, payment, additional data access or external delivery.

## Questions for Savvy's finance and product owners

| Decision | Exact question to resolve |
| --- | --- |
| Fee basis | Are fees based on daily, average, beginning or ending billable AUM; which day-count convention and billing cadence apply? |
| Eligible assets | Which accounts, assets, cash holdings or relationships are fee-exempt, discounted or subject to household tiers? Which system identifies the billable base? |
| Changes in the book | What dates govern additions, withdrawals, transfers, terminations and late/corrected custodian observations? |
| Advisor share | Does the split apply to billed fees, recognized fees, collected cash or another base? How are amendments and retroactive corrections handled? |
| Costs | Which rent, staff, benefits, marketing and other costs are deducted before the split, after the split, shared, subsidized, capped or deferred? |
| Loans | What are principal, interest, repayment priority, caps, shortfall carryforward and termination/clawback rules? |
| Timing | Which service period produces which payout, what is the collection cutoff, and how are weekends, holidays and late receipts handled? |
| Exceptions | What happens to credits, refunds, overpayments, write-offs, disputed fees and negative advisor balances? |
| Reference result | Which closed-period worksheet or ledger is the accepted reference, who signs off, and what cent-level tolerance and rounding policy apply? |
| Product language | What may advisors treat as earned, estimated, pending review or approved? What uncertainty needs to be visible beside the headline number? |

## Questions for Campfire and engineering owners

- Which tenant/entity and roles can supply an approved read-only staging export
  or sandbox connection? Which authentication mechanism is actually configured?
- What are the canonical joins between advisor, client, household, account,
  fee contract, invoice, invoice line and payment? Are invoices ever shared
  across advisors, and where is the allocation rule stored?
- Which payment types represent actual cash in this tenant? The retrieved
  public page documents `CREDIT_MEMO` but did not establish a complete enum.
  Which records prove bank settlement rather than only invoice application?
- How are voids, refunds, reversals, deleted records and late backdated changes
  represented? Is historical source-state reconstruction available?
- Which endpoint covers each needed data set and update watermark? Confirm
  pagination, rate limits, retained versions, replay overlap and checkpointing
  before adding a network client. Avoid an undocumented invoice timestamp filter.
- Where do daily billable AUM observations come from? Campfire invoice data
  alone does not establish the forward-looking asset or contractual fee basis.
- What is permitted in staging and in approved coding assistants? Use the
  company's approved laptop, accounts and data controls for any real-data work.
- Who reviews and operates the eventual product, including access control,
  freshness, discrepancy handling and reconciliation to finance?

## Risks to preserve while extending

An invoice is not cash; a credit memo is not a cash receipt. An invoice void
does not prove its cash was refunded. Unknown payment classification or an
unresolved allocation withholds the reconciliation gap. Comparison uses both
the service period and a separate collection-through date; November fees
expected by December 5 are not a November 30 bank balance.

Do not silently replace the prototype's fee convention with a guessed real
policy. Add a reviewed rule, explicit version and independent reference cases.
Keep the calculation pure, use exact monetary types, retain original evidence,
and keep production actions outside this prototype's read-only boundary.
