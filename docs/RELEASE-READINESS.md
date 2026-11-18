# Savvy review release readiness

Release target: 0.1.0; API contract 0.8.0. GitHub Releases are the changelog.
This records readiness for stakeholder evaluation with synthetic data, not live
customer billing. Final runtime identity is recorded in deployment receipts.

## Presentation and model alignment

The review guide follows the three audiences and both products. The interactive
architecture names implemented adapters/normalization, dated policies, the single
engine, native billing/payables, independent cash, mocked accounting and the
PostgreSQL worker. Actual retained two-product results substantiate each boundary.
Source-map hashes verify linked implementation bytes even when documentation
commits follow the implementation pin. Live connectors/storage/agents and live
Campfire/CLM are explicitly outside the demonstrated implementation.

README review: audience = Savvy reviewers and maintainers; purpose and starting
path appear first; demo, architecture and review guide are linked; a Mermaid
flow explains responsibility and outputs; the three-audience table explains where
to inspect behavior; local availability, synthetic/shared state and integration
limits remain visible; stale private-repo/API-version/deployment statements were
removed. Earlier implementation guides remain linked historical references.
Readability assessment: 4/5 for first-time reviewers; technical setup is delegated
to guides and the full app still benefits from a guided first walkthrough.

## Acceptance and release boundary

Application CI verifies Python/Ruby/PostgreSQL, optimized frontend, both-product
browser flows and reporting. Architecture CI verifies generated docs, source
links, API contracts, desktop/mobile navigation, offline HTML and read-only scope.
The formal shared release gate additionally verifies manifest-owned commands and
exact-commit compliance before an annotated tag and GitHub Release are created.
Never substitute a draft, untested tag or branch-level green for that evidence.

Public demo access is explicitly authorized and confined to the recorded Savvy
hostname/application. Existing data, prior images and databases remain retained.
Before the meeting, verify anonymous HTTPS, local app, worker, disclosures,
architecture/API links and the offline architecture download. Do not publish DB
backups or any runtime credential/configuration snapshots as release assets.
