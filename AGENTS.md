# Savvy Proto

This repository contains an independent synthetic billing prototype in Next.js,
Ruby on Rails, and PostgreSQL.

## Start a session

1. Read [README.md](README.md) for the demo, API, and source index.
2. Read [design decisions](docs/DESIGN-DECISIONS.md) for the audience jobs, rationale,
   plan history, validation, and remaining discovery.
3. Read the **Current review release** section of the
   [handoff](NEW-SESSION-HANDOFF.md) for operating context. Use the
   [closure evidence](docs/FOUR-CAPABILITY-CLOSURE-VALIDATION.md) to check scope.
   Earlier milestone notes are historical. Hosting receipts under `.runtime/`
   exist on the hosting device and are absent from a fresh clone.

## Preserve these contracts

- Keep the same broker experience across both products, with scoped client and
  account drilldowns. Internal Product and Finance have distinct jobs over shared
  records. Preserve Savvy public-site branding.
- Use one `Economics::Engine` for commercial calculation. Supported deal changes
  are versioned API policy data. Keep dated assignment, review tied to the exact
  comparison and document, and exact money and allocation. UI dates show the
  inclusive last day. The API and storage use exclusive ends.
- Retain original source evidence, normalized versions, policy bindings, and exact
  calculation inputs. Keep issued history immutable. Corrections link to originals.
- Keep Savvy-owned obligations, invoices and lines, and custodial instructions.
  Treat confirmed cash and supplied recognition as separate evidence. Campfire
  and CLM remain mocked unless separately authorized. Advisor hierarchy is deferred.
- Keep all fixtures fictional. Keep credentials, real customer data, database
  dumps, dependencies, and runtime files out of Git. No new spend is authorized.
- Keep the local API and database on loopback. PostgreSQL's
  [structure.sql](apps/api/db/structure.sql) is authoritative. Use disposable
  databases for resets and integration tests. Run destructive suites serially.

## Verify changes

| Area | Check |
|---|---|
| Python, import, and deployment guards | `python3 -m unittest discover -s tests -q` |
| Rails and PostgreSQL | `bash scripts/release-domain-check.sh` uses a separate disposable database |
| Browser evidence map | `node --test tests/trace_workflow_cycle.test.cjs` and the browser run in [Architecture checks](.github/workflows/architecture.yml) |
| Frontend, HTTP journeys, and reporting | `./scripts/check.sh`, `./scripts/analytics.sh`, `./scripts/reconciliation-check.sh`, and `python3 scripts/product_http_check.py`. See [Prototype checks](.github/workflows/ci.yml) for setup and execution. |

## Publish or operate

- Use `gh` or an authorized GitHub API for GitHub operations. Keep browser
  automation for the prototype's UI checks.
- Follow [preview operations](docs/DEMO-PREVIEW.md) for the working app and
  [public architecture](docs/PUBLIC-ARCHITECTURE.md) for the standalone site.
  Distinguish the working app from the independently hosted walkthrough.
  Preserve the active frontend slot and retained database.
- Preserve the authorized `public_demo` mode in
  [deploy/device-host.json](deploy/device-host.json). Keep other hostnames' access
  settings intact.
- Follow the Bean release standard. Releases require green exact-commit checks,
  annotated tags, and matching GitHub Release notes.
