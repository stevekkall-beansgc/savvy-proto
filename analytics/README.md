# Synthetic finance crosswalk — first slice

Run `./scripts/analytics.sh` from the root after `./scripts/setup.sh` and starting
the frontend. Requires uv and a running Docker daemon. Dependencies are locked.
This operates only on the isolated fictional PostgreSQL database; no Campfire,
Savvy warehouse or cloud credentials. Anonymous dbt usage reporting is disabled.

The database initializer gives `savvy_analytics` SELECT on approved `raw_demo`
views and write access only to its `analytics` schema. The models neither post
accounting entries nor change source rows. Local demo uses no password and
loopback-only port 55437; this must not be deployed as production configuration.

Model grains are documented in models/sources.yml. Monetary
values are integer USD cents. Operational charge matches, observed cash context,
linked invoice evidence and unknown accounting amounts remain distinct. Receipt
cash shown alongside a charge is CUSTOMER context, not an additive charge-level
measure when a customer has several charges. Never sum alternate projection runs.

The tests check keys, directional grant/reversal conservation, cross-customer/currency scope, join fanout,
opening coverage bounds, source readiness and unknown-vs-zero. The script returns
nonzero on failure. Tables are local candidate reports, not approved financial
publications. No scheduler is configured.

This first slice reads current immutable records through views; it does not
implement a frozen analytics release manifest or historical as-of warehouse
publication. Application runs retain frozen inputs independently. Complete
Campfire replicas, recognition facts, accounting closes, and production least-privilege configuration remain planned.

Reconciliation additions keep separate grains: `fct_invoice_application_history`
records independent application and reversal evidence; `fct_invoice_balance` has
one invoice with NULL applied/open amounts until at least one application has been
recorded. A full reversal leaves evidenced zero. `fct_bank_batch` holds gross,
fee and net exactly once per entity and batch; `bridge_bank_batch_receipt` is a
membership-only bridge. Aggregate bank amounts from batches, not a join to the
bridge. Reversed receipts do not cancel independent evidence; the exceptions mart
flags them. Filter invoice period by its linked charge's service period start and
bank period by batch business date. These are current views, not frozen reviews,
customer net deposits, accounting postings, or revenue recognition.

Exception rows for missing bank and recognition evidence are entity-wide, not a
substitute for a period-specific review. Receipt capacity checks use all active
applications and their captured source amounts; changed source revisions are
flagged independently for review rather than rewriting the original evidence.

Native billing obligations, invoice headers/lines and custodial instructions are
separate commercial representations; do not add them together. Accounting facts
are explicitly mock observations with nullable amounts, not financial postings.
The demo's deferred database conservation trigger scans synthetic tables globally;
it is a local integrity proof, not a production-scale billing control.

`fct_mock_accounting_fact` is one immutable observation, not one current balance.
A commercial object may have multiple observations; do not sum observations across
versions or timestamps. Choose an appropriate as-of observation before interpreting
its reported values, which can remain unknown.
