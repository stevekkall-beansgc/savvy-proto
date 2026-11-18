# Functional demo preview

The functional Rails/PostgreSQL demo is distinct from the public architecture:

- `https://savvy-proto.beanshop.top/`: full application, device-hosted, existing Cloudflare Access protection.
- `http://127.0.0.1:3104/`: the same application on this device, loopback only.
- `https://savvy.beanshop.top/`: public interactive architecture document.

The default example is February 2027. Clients, Product and Finance all use the
retained Alder household records: $1,000 invoice, $600/$400 account allocations,
$500 credit, $300 confirmed refund and $200 still owed. Client billing and advisor
salary/bonus entitlements are labelled separately. No amounts are recomputed by
the interface. Product presents billable assets → terms → charge → allocation;
its modals open retained evidence. Invoice, cash and accounting remain distinct.

Expand **Demo identity** to switch audience or choose **Business book & operations**.
The older book and cash/recognition examples remain available there. They are no
longer appended to the default household screens. This selector simulates scope;
it is not application authentication. Actual agreement documents remain absent;
the real public disclosures retain view/download options.

Fresh setup explicitly installs these fictional examples using
`apps/api/script/seed_presentation.rb`; CI does the same in its disposable database.
Page reads and preview activation never seed data.

## Updating the existing preview

Build and test in an inactive directory. Never rebuild a live Next directory.
Read `.runtime/hosting/activation.json` and the owned LaunchAgent to identify the
active pair; historical build-slot names below are not deployment authority.
Port 3106 is staging only. API slots 3108/3109 are loopback-only; 3102 remains the
source-frozen baseline rollback API.

1. Commit reviewed source. `python3 deploy/preview-control.py candidate-a`
   (or `candidate-b`) verifies both owned preview services, rejects an active or
   unknown slot, holds a shared build/activation lock and builds exact clean source.
2. Build the API from a `git archive` of the same final commit, passing
   `SOURCE_REVISION`. Run it without source mounts, with a read-only filesystem,
   temporary `/tmp`, `SAVVY_IMMUTABLE_PREVIEW=1`, and the retained DB connection.
   Do not run database preparation, migrations or seeds. Image labels and health
   metadata must identify the exact source and disabled reloading.
3. Start the inactive frontend on 3106 with its slot and candidate API URL. Run
   `python3 deploy/preview-control.py candidate-a --record --api http://127.0.0.1:3108 --container CONTAINER`.
   This verifies the staged frontend/API pair, runs read-only browser and HTTP
   acceptance, then binds the exact source, BUILD_ID, served-asset hash and image
   identity in `.runtime/hosting/candidate-build.json`. Set the installed
   `SAVVY_PLAYWRIGHT_MODULE` when needed. Mutations are never part of this check.
4. Push using verified profile `stevekkall-beansgc`. Both **Prototype checks** and
   **Architecture checks** must succeed on the exact candidate/main commit.
5. `python3 deploy/activate-preview.py` performs preflight only.
   `python3 deploy/activate-preview.py --apply` promotes the verified inactive pair
   through the owned clarity service on 3104, preserves Cloudflare Access and
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
