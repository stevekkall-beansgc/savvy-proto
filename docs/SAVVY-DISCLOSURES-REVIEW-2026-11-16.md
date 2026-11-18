# Public disclosures and prototype implications

Reviewed 16 November 2026. Sources: Savvy Advisors [Form ADV Part 2A, March 31, 2026](https://info.savvywealth.com/hubfs/Form%20ADV%20%2B%20CRS/Savvy-Advisors-ADV.pdf) and [Form CRS, March 2026](https://info.savvywealth.com/hubfs/Form%20ADV%20%2B%20CRS/Savvy-Advisors-CRS.pdf), linked from Savvy's website. These concern its advisory business; they do not establish independent-RIA platform prices or an individual advisor's agreement.

## New evidence

ADV Items 4–5 describe household aggregation, ending-value or average-daily-balance billing, advance/arrears cycles, minimums, net-worth and fixed fees, held-away/private assets, proration and returned unearned fees. Items 12/15 describe custodial valuation and statements. Item 14 includes strategy-linked compensation. The document also separates outside expenses and referral costs from client advisory charges.

CRS Item 3 describes salary, discretionary bonuses, equity and some forgivable transition loans. It also mentions hourly planning charges and separate third-party costs. These disclosures do not substantiate the prototype's particular advisor revenue-share percentages, platform charges, promotions or guarantees.

## Design implications and current gaps

These are engineering conclusions, not additional published terms or implemented capabilities:

| Area | Prototype today | Next evidence to demonstrate |
| --- | --- | --- |
| Commercial optionality | One typed interpreter; dated API policies, bands, minima/maxima and allocations | Named policy examples for alternative valuation bases, cycles, minimums and optional services; no new product-specific calculator |
| Balance evidence | Immutable raw arrivals and dated fact selection | Distinguish reported value, eligible billable value and excluded holdings; explain selected valuation date, coverage and corrections |
| Billing aggregation | Account-level examples; advisor parent/child model deferred | Define fee-group membership and allocate a group fee back to invoice lines; household pricing is a separate decision from advisor hierarchy |
| Lifecycle | Exact obligations, one-time events, invoices, credits and independent applications | Mid-cycle onboarding/termination, prepaid unearned amounts and separately evidenced refunds; service, invoice, due and cash dates remain distinct |
| Compensation | Advisor-share policy examples and governed one-time requests | Separately typed bonus/transition-assistance inputs; a loan principal, forgiveness event, salary and equity award must not collapse into advisory fee revenue or payout cash |
| Cost transparency | Scoped statements and source lineage | Identify who charges, earns and pays each line; distinguish our assessed fees, outside observed charges and embedded costs; never imply a complete cost total when evidence is missing |
| Finance | Supplied recognition schedules and independent mocked postings | Finance-approved accounting treatment and schedules per obligation; public fee disclosures do not determine recognition policy |

The medallion path remains original evidence → normalized billable facts and policy assignment → the single engine's detailed results → statement/reporting rollups. Different valuation and billing cadence belong in API policy and evidenced inputs. Raw arrivals need not become the calculation or statement cadence.

Keep Campfire and CLM mocked. Do not activate new commercial rules from a disclosure. Obtain the governing agreement before binding a policy to an actual relationship.

## Delivered document experience

Both documents appear separately under **Savvy disclosures** in Agreements & terms and Product's agreement explanation. View opens a paged modal; every page is rendered from the unmodified public PDF. Open PDF, Download PDF and an official source link remain available. Original bytes, edition, retrieval date, page count and SHA-256 are recorded in `apps/web/public/disclosures/manifest.json`. They are fixed dated snapshots, not a promise of automatic updates.

The two generated PDF/PNG agreements, output copies and generator were removed. Existing synthetic database document/version references and immutable review history remain intact. The agreement viewer retains exact document/version matching with an empty registry; disclosures are never a fallback agreement.

## Preview and validation

The new frontend was built in `.next-disclosures` while both existing previews continued running. Port 3104 is served by the existing clarity LaunchAgent, now configured with `SAVVY_BUILD_DIRECTORY=disclosures`; port 3103 and its `.next` build remain untouched. Retain older build directories for running/rollback references; never build into the active directory.

Validation: optimized production build and TypeScript pass; 66 non-mutating document/statement HTTP checks and 50 scoped audience checks pass. All 33 page images are served, PDF bytes match manifest hashes, generated file URLs return 404, and scoped amounts remain unchanged. Browser acceptance confirmed ADV first/last controls, CRS page navigation, source/open/download link destinations, Escape dismissal and focus return. Browser download-event capture timed out; file availability and download attributes were verified independently. Screenshot: `artifacts/medallion/savvy-real-disclosures.jpg`. No database mutations or backend code changes were required.
