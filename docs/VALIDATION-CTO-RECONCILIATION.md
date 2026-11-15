# Reconciliation validation — 13 November 2026

All data is fictional, all checks local. No deployment or external provider writes.

| Check | Observed result |
|---|---|
| Original Python reference | 49 tests passed; legacy SQLite resource warnings remain |
| Full Ruby/PostgreSQL suite | 65 tests, 1,203 assertions, zero failures/errors/skips; seed 61409 |
| Independent stress run | 11 tests, 167 assertions; seed 48123; bounded races and rollback |
| Rails eager loading | `zeitwerk:check` passed |
| Final Next.js build | Optimized build and TypeScript passed after final responsive correction |
| Retained-data dbt build | 14 models + 41 data tests, 55 PASS; analytics source UPDATE=false |
| Populated canonical reporting | 55 PASS plus independent SQL amount/membership/conflict assertions |
| Actual HTTP boundary | 19 checks passed, zero accepted mutation commands |
| Logical recovery rehearsal | Eight public tables exactly match one exported source snapshot after restore |
| Prior history preservation | All baseline rows unchanged across six demo tables; new evidence appended only |
| Browser desktop/mobile | Finance record/freeze/correct flow, read-only saved review, advisor exclusion, duplicate batch error, 390px fit |

The complete regression log is `artifacts/cto-readiness/regression.txt`. Separate
build, HTTP, restore, history, populated reporting and frozen-review JSON evidence
are in that directory. The independent scenarios and limits are detailed in
[CTO-STRESS-REPORT.md](CTO-STRESS-REPORT.md).

## Reproduce

After `./scripts/setup.sh`, run sequentially (the test database is shared):

```sh
./scripts/check.sh
./scripts/analytics.sh
./scripts/reconciliation-check.sh
python3 scripts/http_check.py
python3 scripts/recovery_check.py
```

The HTTP check needs the local API running. The populated reporting rehearsal
clears only the explicitly guarded `_test` database and creates temporary dbt
configuration. Recovery exports a consistent PostgreSQL snapshot, restores to a
unique disposable database, compares exact public-table row fingerprints and
removes it. Neither replaces the retained database. All owned services are stopped
at handoff; `./scripts/start.sh` reopens the local preview after setup.

## Independent review and fixes

Terra reviewed another lane's work in addition to its own validation. Review found
and resolved inconsistent current-view read risk, missing unknown-axis exceptions,
missing captured receipt provenance, unknown receipt status becoming zero, and
bank zero-versus-unknown reversal semantics. Reporting review added missing-axis
exceptions and a cross-revision receipt-bound check. Recovery review found an
unbounded output read and a cleanup path that could skip dropping the scratch
database; bounded reads and nested cleanup now address both. Browser review
replaced manual cents/ID entry with exact dollar inputs and evidence choices,
wrapped lineage text, and fixed a mobile saved-review selector overflow.

The frozen review was captured before a correction, then queried after correction
and an API restart. Every stored field matched exactly; only `later_evidence` and
`late_exceptions` differed. The prior $1,770 projection and all original rows were
also preserved. Mobile document width was 390px at a 390px viewport; the review
selector ended at 355px. Financial tables retain their horizontal scroll within
their panels. Desktop/mobile screenshots are saved with the validation evidence.

These are bounded local quality checks, not a sustained throughput benchmark,
distributed crash-safety proof, production recovery guarantee, real authorization
audit, accounting approval or completion of all S01–S30 cases. JSONB history has
application immutability controls, not independently enforced tamper-proof storage.
