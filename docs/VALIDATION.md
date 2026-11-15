# Validation update — November 13, 2026

The standalone working copy passed `python3 -m unittest discover -s tests -q`:
49 tests, including the original synthetic forecast and separate reporting
experiment. `node --check web/app.js` also passed. These checks do not verify
Savvy data or contracts, commercial override precedence, bidirectional
prepurchases, dimensional guarantees, a legal review workflow, an internal feed,
or live system access. Those capabilities are not implemented. Source text was
updated to show all recorded claims and qualifications; browser interaction of
this revision has not been rechecked. See [scope and evidence](EVIDENCE-AND-SCOPE.md).

Historical validation follows. It applies to the earlier prototype revision and
should not be read as current deployment or Savvy acceptance evidence.

---

# Validation evidence

Recorded November 13, 2026. This report describes this prototype, not Savvy or
Campfire production behavior.

## Passed

`python3 -m unittest discover -s tests -q`

**45 tests passed** after integration and the independent review corrections:

- 22 engine tests: independent arithmetic references, fee/expense treatment,
  effective contract dates, loan caps, collection scenarios, exact cent
  reconciliation, history unchanged by future scenarios, and invalid inputs.
- 17 adapter tests: cash versus credits, stable record IDs, repeated and
  out-of-order delivery, retained revisions, payment voids, invoice cancellation,
  precision, currency, explicit mappings and collection dates.
- 6 HTTP/artifact tests: actual local HTTP calculation, rejected unsupported
  inputs, request-size/content-type limits, static file isolation, all 12 named
  advisor/scenario combinations, independently recomputed export checksums and
  standalone preview construction.

`node --check web/app.js` passed JavaScript syntax validation.

`python3 build_preview.py` generated the standalone HTML with exact Python
snapshots, embedded CSS and JavaScript, and no external runtime dependency.
The offline preview permits the four named scenarios for each advisor; custom
slider inputs require the local Python server.

The local server started successfully at `http://127.0.0.1:8766`. The HTTP tests
also start a fresh loopback server on an ephemeral port and exercise its actual
request handlers.

## Independent review

A separate read-only reviewer examined the engine and adapter. Two accounting
issues were reproduced and corrected:

1. An invoice cancellation no longer erases an active cash receipt. The payment
   remains observed, its allocation is flagged, and the comparison is withheld
   until the allocation is resolved. A payment's own void still removes it.
2. Reconciliation now carries the November service period, November 13 observed
   cutoff and December 5 collection-through date separately. The server passes
   the engine's explicit payout date; missing or invalid horizons fail closed.

The reviewer read back both fixes and ran four focused regression checks.
Both original findings were verified resolved. No material arithmetic defect
was identified under the explicitly documented synthetic contract.

## Blocked / not verified

Browser interaction and visual/responsive QA were attempted but did not run:

- The installed Python Playwright package had no matching bundled browser.
- Launching the system Chromium failed because its process-singleton socket
  was denied by the executor: `socket() failed: Operation not permitted`.
- The available separate desktop browser could not reach this workspace's
  loopback server: `net::ERR_CONNECTION_REFUSED`.

Therefore, no passing browser, screenshot, layout, mobile, download-button or
accessibility claim is made. JavaScript syntax and artifact generation passed;
these do not replace a browser test. Run the included `browser_smoke.py` in an
environment with a working Chromium to close this specific gap.

The automatic native Codex fork failed with a read-only filesystem error. The
implementation was completed in the current workspace; `CODEX-HANDOFF.md` is a
continuation document, not a running Codex task.

## Outside this validation

No real Campfire/Savvy data, credentials, live API, webhook delivery, tenant
configuration, production access control, deployment, accounting write or
payment was exercised. No Docker build was attempted. Shared Core design assets
were reused unchanged; the unrelated full Core CI suite was not run.

Before using real records, agree a representative contract and an accepted
closed-period finance calculation, then reconcile each component and date.
