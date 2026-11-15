# Review of the interrupted rewrite

Reviewed 13 November 2026 before extending the archive from original commit
`1daac22` (the archive contains no Git history). The original archive is retained
at `/Users/stephenkall/Downloads/savvy-execution-handoff.zip`.

The interrupted `apps/` directory contains 19 files: a pure Ruby evaluator,
Rails boot/configuration, three models and one migration. It has no controllers,
GraphQL schema, seeds, Ruby tests, dependency lock, frontend or runnable setup.
It must not be described as a working Rails application.

Findings to resolve before using its output:

1. **High: repeated prepaid coverage.** Every fact reads the same grant opening
   balance. Two $600 obligations can each consume $600 of one $1,000 grant in
   a single projection. Maintain an isolated, shared simulation balance and
   roll it back if any part of a fact fails; never mutate the supplied snapshot.
2. **High: premature cent rounding.** The evaluator allocates rounded fee cents
   before applying rates. On a one-cent fee split equally between 40% and 80% shares,
   rounding the fee allocation first can yield zero entitlement instead of one
   cent. Preserve rational weighted rates, round the total once per source fee
   line, then allocate recipient cents by stable largest remainders. Display fee
   allocations must not drive the monetary calculation.
3. **High: scope checks are incomplete.** The migration's allocation foreign key
   references tenant only; a mismatched entity can be persisted. Policy headers
   are not checked against snapshot scope. Enforce composite scope in PostgreSQL
   and at service/domain boundaries.
4. **High: cutoff and partial results.** Facts are not checked against knowledge
   cutoff; later facts may enter an earlier run. A fact may append a successful
   advisor line before another advisor fails. Validate knowledge times and commit
   each source fact atomically; keep failures explicit rather than zero.
5. **Medium: input and policy validation.** Dates compare as raw strings;
   duplicate facts, negative/duplicate assignment weights, unsupported selectors
   and missing dimensions are not consistently rejected. The required customer
   dimension is hardcoded rather than governed by the policy profile.
6. **Medium: guarantees lack enforced period/group scope.** A passed `period`
   label does not filter the measurements. Count units can masquerade as money;
   overlapping guarantees are not validated. Limit initial support to typed,
   explicitly scoped mechanisms and reject everything else.

Retain the existing Python implementation and web assets as the reference.
Baseline: `python3 -m unittest discover -s tests -q`: **49 tests passed** on
13 November; Python 3.14 emitted SQLite connection ResourceWarnings. These tests
do not validate any interrupted Ruby implementation.

The continuation is local and synthetic. No remote repository, deployed Site,
Campfire connection, production credentials, payment or external message is
part of the work. The publication pause remains in force.
