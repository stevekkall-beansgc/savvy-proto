# Functional demo preview

The functional Rails/PostgreSQL demo is distinct from the public architecture:

- `https://savvy-proto.beanshop.top/`: full application, device-hosted, public synthetic demo, no sign-in.
- `http://127.0.0.1:3104/`: the same application on this device, loopback only.
- `https://savvy.beanshop.top/`: public interactive architecture document.

The default is **Billing workspace · Both products**. Use Business to switch
between the advisor and independent RIA cases. Both have the same client
experience: grouped clients, account drilldown, issued invoices and applied terms.
The two service periods show real synthetic input flowing through the shared path.
Advisor compensation and reported custody income are separate from billed fees.

Internal Product opens source processing, terms, calculations and native documents
through the four-step overview. Finance opens the connected bill/cash/recognition view and reviews exact corrections. Earnings separates calculated amounts, approved native payables and confirmed payments. The pipeline has PostgreSQL-backed scheduled work and retained execution attempts. Campfire
and CLM remain mocked; supplied payment/accounting observations do not imply a live
operation. Real disclosures retain view/download options; signed agreements remain
absent. Earlier household/book examples remain under Demo identity.

Fresh setup explicitly runs `script/seed_presentation.rb` and
`script/seed_billing_platform.rb` and `script/seed_billing_closure.rb` after schema preparation and base seeds. Page reads
and preview activation never seed. Read `FOUR-CAPABILITY-CLOSURE-VALIDATION.md` for current scope and limits.

The four-capability baseline is served from `savvy-billing-complete-db` at
55441; the prior candidate-b/API3109/database55440 pair remains preserved. Read
actual runtime receipts before assuming a slot/container. Once new writes occur,
switching to an older database would omit those writes; use a forward fix or
reconcile explicitly before rollback.

## Updating the existing preview

Build and test in an inactive directory. Never rebuild a live Next directory.
Read `.runtime/hosting/activation.json` and the owned LaunchAgent to identify the
active pair; historical build-slot names below are not deployment authority.
Port 3106 is staging only. The closure candidate uses a fresh retained clone at 55441; verify actual container names in the activation receipt before connecting. API slots 3108/3109 are loopback-only; 3102 remains the
source-frozen baseline rollback API.

1. Commit reviewed source. `python3 deploy/preview-control.py candidate-a`
   (or `candidate-b`) verifies both owned preview services, rejects an active or
   unknown slot, holds a shared build/activation lock and builds exact clean source.
2. Build the API from a `git archive` of the same final commit, passing
   `SOURCE_REVISION`. Run it without source mounts, with a read-only filesystem,
   temporary `/tmp`, `SAVVY_IMMUTABLE_PREVIEW=1`, and the prepared retained-clone DB connection.
   Do not run database preparation, migrations or seeds. Image labels and health
   metadata must identify the exact source and disabled reloading.
3. Run a worker from the same immutable API image with `bundle exec rails runner script/billing_worker.rb`, using the prepared database. It requires no public port or source mount.
   Start the inactive frontend on 3106 with its slot and candidate API URL. Run
   `python3 deploy/preview-control.py candidate-a --record --api http://127.0.0.1:3108 --container CONTAINER`.
   This verifies the staged frontend/API pair, runs read-only browser and HTTP
   acceptance, then binds the exact source, BUILD_ID, served-asset hash and image
   identity in `.runtime/hosting/candidate-build.json`. Set the installed
   `SAVVY_PLAYWRIGHT_MODULE` when needed. Mutations are never part of this check.
4. Push using verified profile `stevekkall-beansgc`. Both **Prototype checks** and
   **Architecture checks** must succeed on the exact candidate/main commit.
5. `python3 deploy/activate-preview.py` performs preflight only.
   `python3 deploy/activate-preview.py --apply` promotes the verified inactive pair
   through the owned clarity service on 3104, preserves the declared public demo access mode and
   records `.runtime/hosting/activation.json`. The existing route is not rewritten
   if already correct. Failed readiness, changed artifacts or image identity cause
   rollback to the previous frontend/API pair and receipt.

Build and activation refuse concurrent operations, unowned services/routes,
source drift, writable/mounted API containers and stale CI. Neither operation
resets, migrates or seeds data. Original invoices/history and both retained
volumes stay intact. The older 3100 deployment and the previous source-frozen API
remain available for rollback. No new paid infrastructure is provisioned.
This is a preview update; semver releases remain governed by the repository's
release gates and are not created by this script.

The device must remain running and online. The existing login services restart
previews and the tunnel at login; Docker must be running for the API and database.
