# Savvy review guide

Open the [working demo](https://savvy-proto.beanshop.top/) and
[architecture walkthrough](https://savvy.beanshop.top/) in separate tabs.
Both are available without sign-in. The local app is also available at
http://127.0.0.1:3104/ on the presentation device.

## Suggested walkthrough — 15 minutes

1. **Broker experience (4 minutes).** Start in the shared billing workspace.
   Choose the affiliated advisor business, then the independent RIA. Show grouped
   clients before drilling into accounts. Open an issued invoice to see service
   dates, line amounts and applied terms. Open Agreements to view or download the
   real Savvy disclosures; a signed agreement can be attached later.
2. **Internal Product (4 minutes).** Follow an input record through ingestion,
   normalization, dated policy assignment and calculation. Open the frozen inputs,
   policy and result. Show a versioned commercial policy: changing supported
   terms uses the API and the same engine. Inspect queued work and its attempts.
3. **Internal Finance (4 minutes).** Open Finance and compare the bill, confirmed
   cash and outstanding balance. Follow credit/refund evidence. In Earnings,
   distinguish calculated compensation, approved payables and confirmed payout.
   Open the accounting package and supplied recognition outcome.
4. **Architecture (3 minutes).** Show the mental model first, then the component
   view and billing engine. Click a component for its responsibilities and source.
   Use the two executed product examples to connect the diagram back to the app.

## Questions for the discussion

- Brokers: can you explain an invoice, adjustment or payout without asking Finance?
- Product: do the data lineage, policy lifecycle and single engine fit Savvy's model?
- Finance: are native claims, cash matching and recognition clearly separated, and
  what fields would Campfire need in the handoff?

## Scope to state once

This is an independent prototype with fictional records and shared demo state.
Campfire and CLM are mocked; the disclosures are real public documents. No real
collections, payments, legal approvals or accounting posts occur. The hosted app
runs from this device; the architecture/API documents have independent hosting.
Live integrations and production security/operations are future work.

## Presentation setup

Keep the Mac on AC power, online and logged in, with Docker Desktop running.
Open the local app before the meeting so it is ready even if the meeting network
blocks the hosted domain. Keep the architecture HTML download as an offline copy;
it includes all three views, explanations and recorded examples. Offline code
links still require a network connection. The full app needs its local API/DB.

Return to the default shared workspace after exploring historical demo identities.
Public changes affect shared synthetic state; preserve the prepared records rather
than resetting them before or during the meeting.
