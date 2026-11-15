# Hosting status — 15 November 2026

The owner authorized persistent hosting using existing infrastructure only, with
no new spend. The full app remains local at http://127.0.0.1:3100. Its PostgreSQL
volume retains the existing synthetic history and scheduled proposal.

The current full application is Next.js → Rails → PostgreSQL. A source repository
alone does not host it. Its API currently enforces loopback origins and uses
simulated roles; those are deliberate local boundaries, not a hosted login system.

Discovery found an existing owner-private Sites project, created November 13 and
never deployed, bound locally by ignored `.openai/hosting.json`. It supports static
or Cloudflare Worker deployment, not the existing Rails/PostgreSQL runtime. The
historical `dist/` output is the older Python-reference preview and must not be
published as though it were the current workspace.

No running OCI compute instances were returned across accessible compartments in
the configured us-ashburn-1 region. The configured GCP project's Compute API is
disabled; it was not enabled. Tailscale's local daemon is unavailable. No new
server, paid service, subscription or provider account was created.

A current private walkthrough can use the existing Sites project with read-only
workspace data. It must retain the current UI, distinguish saved scenario data
from interactive writes, and cannot claim server-backed edits or shared durable
PostgreSQL storage. The owner was asked whether to publish that bounded walkthrough
or keep only the source backup. The full app needs an existing compatible host or
separate authorization before a different hosting architecture is introduced.
