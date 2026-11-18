# Public architecture document

Architecture hostname: **https://savvy.beanshop.top/**.
Source: **https://github.com/stevekkall-beansgc/savvy-proto** (public).

This publication serves the standalone architecture document, not the Rails
application. It has no login, provider connection, GraphQL endpoint, database,
local-file viewer, payment action or accounting posting. The public synthetic
device-hosted app at `savvy-proto.beanshop.top` remains a separate route.

## Build and verification

```sh
python -m pip install -r docs/api/requirements.txt
python3 docs/api/build.py
python3 scripts/api_contract_check.py
python3 docs/architecture/build.py
python3 scripts/package_architecture.py
```

The allowlisted publication directory is `.runtime/publication/site/` and
contains only `index.html`, `404.html`, `_headers`, `robots.txt`,
`build-metadata.json`, `api/index.html`, `api/openapi.yaml` and `api/schema.graphql`. Credentials, repository source files and local service
scripts are not copied into it. The HTML retains selected source excerpts and
links to the exact source commit on GitHub. There are no local-file links.

The CSP allows only the exact embedded script hashes, embedded fonts/images and
inline styling; network connections and framing are disallowed. The document is
publicly reachable but marked noindex as an independent prototype.
`Cache-Control: public, max-age=0, must-revalidate, no-transform` preserves the
published HTML bytes and prevents zone-level analytics injection from conflicting
with the script hashes. This affects this document only; no shared analytics
configuration is changed.

`.github/workflows/architecture.yml` runs the reproducible builder, source-pin
checks, static packager and browser acceptance against the exact commit. It does
not access Cloudflare credentials or deploy automatically.

## API reference

The public header links to `https://savvy.beanshop.top/api/`, with OpenAPI YAML
and authoritative GraphQL SDL downloads. The reference documents the implemented
GraphQL transport, all 23 query/mutation fields, command enums and 36 typed
policy, billing, earnings, cash, accounting and worker command examples. It has no live request
execution or credential entry. MCP/WebMCP interfaces are explicitly future work.

`docs/api/build.py` generates the YAML and self-contained page from the SDL and
source-pinned metadata. `scripts/api_contract_check.py` validates OpenAPI 3.1.1,
GraphQL documents/variables, action enums, typed command examples and source
drift. `--live` performs only three loopback reads; it sends no mutations.
The architecture workflow checks generation, validation and desktop/mobile
reference navigation, filtering and downloads.

## Publish

Commit the reviewed document and wait for `architecture-compliance` to succeed
on that SHA. Fast-forward remote `main` to the checked candidate. Then run:

```sh
python3 deploy/publish-architecture.py --wrangler /path/to/installed/wrangler/bin/wrangler.js
```

The script refuses a dirty tree, a candidate differing from remote main, or an
exact commit without successful architecture CI. It retrieves the existing
Cloudflare credentials through BeanLaunch at runtime, passes them only in the
Wrangler process environment, and never writes them to source, disk or argv.

Cloudflare Pages project: `savvy-architecture`; production branch: `main`.
The script associates only the requested custom hostname and refuses to replace
an unrelated DNS record. It uses static Pages assets with no Functions, Worker,
KV, database, paid-plan change or new server. Existing account infrastructure
supplies the hosting and DNS.

The local receipt is `.runtime/publication/deployment.json`. Verify public
HTTPS without cookies, no authentication redirects, the four-step engine view,
modal/code links and download. Compare live `/build-metadata.json` and HTML hash
with the checked commit's bundle. DNS and certificate activation can complete
after the upload; observe the custom-domain status before declaring it live.

## Updates and rollback

Keep the prior deployment ID before an update. A rollback restores a prior
static Pages deployment; it never changes commercial policy, retained database
state or the full application route. Source-code links remain pinned to the
implementation version inspected by the document.

## Public repository review

Before changing visibility on 18 November 2026, all four reachable commits and
420 historical blobs were reviewed for credential patterns, credential file
paths and non-placeholder literal secret assignments; none were found. Source
fixtures were authored synthetic records, and the disclosure documents were
unchanged public Savvy publications. No Git history rewrite was required.
