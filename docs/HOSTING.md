# Savvy demo hosting

The public full app is **https://savvy-proto.beanshop.top/**; the local app is
**http://127.0.0.1:3104/**. Public architecture and API documents are independently
hosted at **https://savvy.beanshop.top/**. No sign-in is required for the synthetic
demo. Simulated audiences and roles demonstrate workflows, not production identity.

## Current application

Cloudflare HTTPS → dedicated Savvy Tunnel → loopback Next.js 3104 → immutable Rails
API → retained PostgreSQL. A worker uses the same API image and database for queued
normalization/evaluation. API and database ports remain loopback-only; there is no
public Docker port or inbound router rule.

Read `.runtime/hosting/activation.json` for the exact active commit, frontend slot,
API image and endpoint. Read `.runtime/hosting/public-access.json` for public access
verification and `.runtime/publication/deployment.json` for static publication.
Inspect the API container's `PGHOST` before connecting to a database. Historical
milestone documents and old port numbers are not deployment authority.

The four-capability baseline uses `savvy-billing-complete-db`, volume
`savvy-billing-complete-data`, loopback 55441. The prior database at 55440 and the
older retained volumes remain preserved. Never reset, reseed or migrate an active
retained database to deploy a build.

## Public access and scope

The owner explicitly authorized public access to all synthetic demo experiences.
`deploy/device-host.json` declares `public_demo`; `deploy/public-demo.py --apply` can
add an Everyone bypass to only the recorded Savvy Access application and disable
its tunnel-origin JWT requirement. The existing owner policy remains available.
The installed token is Tunnel-scoped, so the initial policy was saved through the
Cloudflare dashboard and `--origin-only --apply` verified the public origin.
Other hostnames, applications, identity providers and routes are unchanged.
The tool validates ownership, records prior configuration and rolls back a failed
change. Activation checks preserve the declared public mode on future updates.

Public viewers can inspect the prepared synthetic records. Start your own demo
creates a separate PostgreSQL scope from the fictional fixtures. An HttpOnly cookie
carries a random capability for 24 hours. Start again revokes that scope and returns
to the sample views. Saved workspace records remain available for operator recovery.
The prototype admits up to 200 visitor scopes per database by default. Creation is
serialized, with a busy response during concurrent setup. If capacity is reached,
the read-only samples remain available. The app has no real customer connection, credentials-entry flow,
payment execution, real agreements or live Campfire/CLM posting.

## Presentation availability

The Mac must remain powered, connected and logged in with Docker Desktop running.
Owned login services restart the frontend and tunnel; Docker restart policies
cover API, worker and database. AC sleep prevention does not override manual
sleep, lid closure, logout or network loss. This is device hosting, not a claim
of independent cloud uptime. The local app is usable without external ingress;
the downloaded architecture HTML is self-contained.

## Updates, backup and rollback

Follow [preview operations](DEMO-PREVIEW.md): clean committed source, immutable API
and worker images, an inactive frontend slot, green exact-commit application and
architecture CI, recorded acceptance, guarded activation and public verification.
For schema changes, restore a fresh clone and compare every pre-existing value.
Activation never seeds, migrates or calculates.

Source in GitHub does not back up the retained Docker volume. Take a logical
`pg_dump -Fc` of the verified active database before releases; keep it ignored and
outside public release assets. Restoring must target a new disposable/retained
clone. Keep the prior image, slot, database and receipts. A rollback after new
writes requires reconciliation; switching to an old DB would omit those writes.

Public-access rollback: remove only the recorded public policy, then restore the
saved tunnel access configuration from `.runtime/hosting/public-access-before.json`.
Reconcile `access_mode` in source before further activation. Credentials are read
at runtime from the existing BeanLaunch mirror and never written to source or
process arguments. No new paid infrastructure is required.

[Historical November 15 setup](HOSTING-HISTORY.md) is retained for provenance.
