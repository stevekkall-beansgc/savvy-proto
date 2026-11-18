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
The current candidate uses `SAVVY_BUILD_DIRECTORY=presentation` and
`apps/web/.next-presentation`; choose a different slot for subsequent updates.
Port 3106 is a temporary staging listener and is not publicly routed.

1. Build the inactive slot, run `scripts/presentation_ui_check.cjs` against its
   loopback staging listener, and run the read-only HTTP checks. The browser check
   also runs in the existing Prototype checks workflow.
2. Commit and push with verified profile `stevekkall-beansgc`. Wait for successful
   **Prototype checks** on that exact commit, including the full domain suite,
   reporting, origin checks and the new browser journey.
3. Record the candidate's commit and `.next-presentation/BUILD_ID` in
   `.runtime/hosting/presentation-build.json` after building that exact source.
4. `python3 deploy/activate-preview.py` verifies readiness without changes.
   `python3 deploy/activate-preview.py --apply` updates only the owned clarity
   preview service and the existing Savvy tunnel route. It retains the Access
   audience, team and required JWT validation, confirms allowed/denied origins,
   and saves local rollback copies and an activation receipt.

The script checks the exact remote main and CI, refuses unowned services/routes,
and restores the previous service and tunnel configuration on a failed activation.
It never resets, migrates or seeds a database. Both retained volumes and the older
port 3100 deployment stay intact. No new paid infrastructure is provisioned.
This is a preview update; semver releases remain governed by the repository's
release gates and are not created by this script.

The device must remain running and online. The existing login services restart
previews and the tunnel at login; Docker must be running for the API and database.
