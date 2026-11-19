# Savvy Proto

Independent synthetic prototype. Read `README.md` for the current demo and source
index, `NEW-SESSION-HANDOFF.md` for the active baseline, and
`docs/FOUR-CAPABILITY-CLOSURE-VALIDATION.md` for implemented scope and verification.
`docs/WORKSPACES-MILESTONE.md` and `docs/VALIDATION-WORKSPACES.md` describe an
earlier milestone.

- Preserve Savvy public-site branding and the explicit Broker/Internal experiences.
- Savvy owns commercial billing obligations, invoices/lines and custodial instructions.
  Campfire and CLM integrations remain mocked unless separately authorized.
- Keep exact money, service-date selection, immutable history, scoped identities and
  exact comparison/document-bound proposal review. PostgreSQL `db/structure.sql`
  is authoritative; do not replace it with schema.rb.
- All fixtures must remain fictional. Never commit credentials, real customer data,
  database dumps, dependencies or runtime files. No new spend is authorized.
- Use gh or an authorized GitHub API for GitHub operations; never browser automation.
- Local API and DB remain loopback-only. Test resets are guarded to the synthetic
  test database. Never reset retained main data or run destructive suites concurrently.
- Appropriate checks: `./scripts/check.sh`, `./scripts/analytics.sh`,
  `./scripts/reconciliation-check.sh`, `python3 scripts/product_http_check.py`.
  Read the validation document for scope and setup. UI copy uses inclusive last-day
  dates; the API/storage use exclusive ends. Preserve that conversion.
- Do not replace the full Rails/PostgreSQL app with an unlabelled static fallback.
  Hosted walkthroughs must be distinguished from the interactive local application.
- Releases follow the Bean release standard, with green exact-commit CI, annotated
  tags and matching GitHub Release notes. GitHub Releases are the changelog.

## Test commands

- Unit and deployment guard checks: `python3 -m unittest discover -s tests -q`.
- Rails/PostgreSQL integration: `bash scripts/release-domain-check.sh` uses its
  own disposable test database and never the served database or frontend slots.
- Full frontend, browser and reporting acceptance runs in Prototype checks.
- Source-linked architecture and API acceptance runs in Architecture checks.
- Public demo access is explicitly authorized in `deploy/device-host.json`.
  Preserve this mode on updates; never change access for any other hostname.
