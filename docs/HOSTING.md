# Device hosting — 15 November 2026

Live private app: **https://savvy-proto.beanshop.top/**

The owner authorized the full application on this Mac, using existing
Cloudflare/GCP infrastructure with no new spend. This is the current interactive
Next.js → Rails → PostgreSQL application; Campfire and CLM remain mocked.
Private source: https://github.com/stevekkall-beansgc/savvy-proto.

## Traffic and access

Cloudflare DNS/TLS → dedicated Savvy named Tunnel → loopback Next.js port 3100 →
loopback Rails port 3101 → retained PostgreSQL volume (port 55437).

The entire hostname, including /api/graphql, has an owner-only Cloudflare Access
policy for the existing owner Google/email identity. The existing Google and
email-code identity providers handle login. The tunnel also verifies the app's
Access JWT before forwarding. Unmatched hostnames return 404. No public API/DB
port, router inbound rule, bypass policy or service token was added. The isolated
subdomain does not replace the apex site or existing routes. Simulated product
roles are separate from this authenticated owner identity.

Next.js permits the exact HTTPS origin via SAVVY_PUBLIC_ORIGIN; localhost still
works. Unrelated origins, suffix lookalikes and insecure HTTP are rejected.
Non-secret resource IDs are in deploy/device-host.json. The tunnel token is
fetched at launch through Cloudflare's token API using the existing BeanLaunch
credential mirror, then passed through its environment, never argv or disk.
No new Secret Manager version, paid tier or rented server was created.

The configuration follows Cloudflare's current [origin JWT documentation](https://developers.cloudflare.com/tunnel/reference/origin-parameters/)
and [remote tunnel API](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel-api/).

## Persistence and availability

Two user LaunchAgents run after login and restart on exit:

- com.beanlabs.savvy-proto.app starts the existing Docker stack, waits for API
  health, then serves the optimized frontend. Docker services have restart policies.
- com.beanlabs.savvy-proto.tunnel retrieves the tunnel token in memory and starts
  cloudflared. Path normalization is explicitly enabled.

The app prevents automatic system sleep on AC power while serving, without
changing global sleep settings. This does not override manual sleep, lid closure,
shutdown, network loss or logout. The Mac must stay powered, connected and logged
in, with Docker Desktop running. This is not independent cloud uptime.
The PostgreSQL volume retains history across process/container restarts. GitHub
stores source/seed fixtures, not the retained database volume.

## Operate and recover

Build with npm --prefix apps/web run build. Install/reload both login services
with python3 deploy/install-device.py. The installer only manages the two Savvy
labels and refuses another working directory. First-time dependency/API image
setup remains ./scripts/setup.sh. Keep this source path or reinstall after moving.
Do not start a competing frontend on port 3100 while its login service owns it.

Inspect launchctl print gui/$(id -u)/com.beanlabs.savvy-proto.app and the same
.tunnel target; docker compose ps shows the API/DB. Logs are ignored under
.runtime/hosting/. python3 scripts/host_check.py verifies actual proxy boundaries.
Restart one job with launchctl kickstart -k against its gui/<uid>/<label> target.

To suspend hosting, launchctl bootout both Savvy targets; merely killing a process
will cause restart. Keep the Access policy. To retire it, remove only the recorded
Savvy DNS record after checking its ID, then retire its dedicated tunnel/app.
Do not change other sites or delete the database volume.

For upgrades: commit/push reviewed source, wait for exact-commit CI, build and
restart the app service. Do not reset or reseed main history to deploy UI changes.
Take a logical backup before future schema changes; the recovery checker restores
only into a disposable database.

## Validation

Optimized frontend/TypeScript build, shell/Python syntax, six actual proxy origin
checks and 21 product HTTP checks passed. Anonymous edge requests redirect to
Access login. Browser Google sign-in as the owner loaded live earnings
($1,750/$1,000/$750) and the retained November 16 scheduled proposal, its separate
$850→$950 example, and both reviews. The two installed plists contain no tokens.
A service restart check verifies app/tunnel recovery without replacing data.

The earlier unpublished Sites placeholder is unused. It was not substituted for
this application. No real provider integration, payment, signature or real
company/customer data was introduced.
