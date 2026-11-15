# Broker and Internal workspace milestone

14 November 2026. Astra finalized the bounded contract; Terra agents implemented
the commercial domain, interface and native billing/reporting, then cross-reviewed
and independently stress-tested them. Root integrated, rehearsed migration and
restore, and exercised the actual desktop/mobile journeys. All data is fictional.
See [validation](VALIDATION-WORKSPACES.md) for evidence and practical limits.

## Product changes

| Walkthrough feedback | Implemented behavior |
|---|---|
| Separate broker and internal jobs | Explicit Broker and Internal experiences, distinct navigation and server-enforced simulated advisor scope. |
| Remove process subtitles, snapshots and technical assumptions | Earnings leads with earned compensation, coverage, estimated payment and customer drilldown. References are disclosures; no snapshot/hash/export cards. The monthly-floor subtitle is removed. |
| Show existing agreements | Broker Agreements shows current, historical and approved-upcoming terms, dates and illustrative document/version references. Client fee terms and advisor compensation remain distinct. |
| Rate history and future dates | One PostgreSQL commercial_rates table, immutable configurations, half-open start/end dates, optional ends, historical versions and separately scheduled future configurations. |
| Replace managed-service override | Targeted promotion category with customer/product dimensions, optional signup-window eligibility and explicit conflict priorities. Friendly names appear to the broker. |
| Policy Studio is internal | Internal Commercial terms contains the schedule, current earnings context and proposal preparation. |
| Move clause editing toward CLM | No embedded clause editor. Approvals shows a suggested change summary, exact configuration/comparison and versioned mock CLM reference with separate simulated Legal/Finance reviews. |
| Sources/Runs, Collections, Settlement, Reconciliation and Review packet distract | Removed from primary navigation. Earlier code, APIs, records and validation remain retained. |
| Keep billing close to Savvy's model | Typed Savvy-owned obligations, invoices/lines and custodial instructions with source, customer, account, client-term and assignment lineage. |
| Keep providers mocked | Separate mock accounting observations and mock CLM document/review references; no network adapters, provider credentials or external writes. |

Official Savvy public-site logo, fonts and colors remain in use; provenance is in
[the brand reference](SAVVY-BRAND-REFERENCE.md). No internal style guide was supplied.

## Try the local review

Open http://127.0.0.1:3100. The running preview starts in Broker → Earnings.
Expand Cedar to inspect its native invoice and two lines; Maple has a separate
invoice. Open Agreements to see governing and approved-upcoming illustrative terms.

Internal → Advisors → Commercial terms opens an advisor's current configuration
and earnings context. Jordan's Birch customer demonstrates the custodial instruction
route, with execution explicitly unavailable. Create a proposal with an effective
date, optional rate ends, friendly promotion names and supported eligibility.
Saving is separate from comparison, review, scheduling and becoming effective.

In Approvals, compare the current book or the independent hypothetical future
signup. Both simulated reviewers bind the exact comparison and mock document
version. A changed source manifest, base, comparison or document prevents reuse of
stale approvals. Scheduling is atomic and idempotent. No document is signed.

The retained local volume includes a reviewed proposal effective November 16:
`proposal-77c0b64f-1f9b-4ecc-aeaf-c7f6104948d3`. It has an ongoing 80% standard,
87% November promotion and a 95% Planning welcome promotion within the first seven
days after signup. The separate future example changes compensation from $850 to
$950. Current November 13 earnings remain $1,750, coverage $1,000 and estimated
incremental payment $750. The demo business date is intentionally fixed.

Actual future earnings are blocked when the retained observations do not cover
that date. Hypothetical examples do not redate or rewrite those observations.

## Data and calculation boundaries

The original Ruby economics engine remains intact. A narrow commercial adapter
selects persisted rates and passes supported fixed-fee observations to it. Selection
is targeted promotion → advisor-wide promotion → standard, using service dates and
replacement shares. Signup windows are half-open; missing required signup evidence
blocks the affected calculation. Existing guarantees are copied unchanged in new
proposals; expanded guarantee/loan/expense authoring is outside this milestone.

Each new database table is scoped. Rate exclusions reject overlapping standard and
general-promotion periods within a configuration, and identical targeted scopes;
service validation handles intersecting eligibility. Billing uses composite foreign
keys and deferred conservation checks. Invoice lines retain obligation and source
lineage, including explicit mappings to existing Cedar/Maple invoice identities.
Compensation or mock accounting changes never alter client invoice amounts.

Commercial obligations, invoice amounts and custodial instruction amounts are
different representations of the same underlying fees and must not be summed
together. Mock accounting observations have their own non-additive history.
Unknown application, AR, recognition or execution facts remain null. Earnings do
not establish bank settlement, accounting recognition or payment execution.

The SQL schema export is authoritative. `db/structure.sql` preserves the billing
function, five deferred triggers and two exclusion constraints that a Ruby schema
dump would omit. Fresh load, existing-volume backfill and seed replay were checked.
All 34 prior evidence records and 25 prior operations remain unchanged, including
the earlier $1,770 draft-policy run and all retained grant/receipt/reversal history.
That draft was never activated, so the new product correctly starts from v1.

## Remaining production work

This is a bounded local demonstration, not completion of the original S01–S30 plan.
Identity is simulated; no production authentication, real Savvy schema, tenant
integration, actual daily-AUM feed, real legal approval or provider behavior was
validated. Reuse Savvy's actual billing models before proposing production schema
migrations. Campfire posting/reconciliation and CLM negotiation/execution belong
behind real integration contracts, not inferred mock behavior.

Fixtures have one broker/account/assignment per obligation and multiple invoice
lines; general many-to-many allocation remains future work. The deferred billing
check scans the synthetic tables globally and needs a production-scale design.
Stress checks are bounded races, not capacity testing. Earlier legacy APIs remain
available for reference; new product commercial rates are authoritative only for
the new workspace path. No public deployment or external contact was made.
