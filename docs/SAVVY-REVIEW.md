# Savvy review guide

Open the [working demo](https://savvy-proto.beanshop.top/) and
[architecture walkthrough](https://savvy.beanshop.top/) in separate tabs.
Both are available without sign-in. The local app is also available at
http://127.0.0.1:3104/ on the presentation device.

## Suggested walkthrough for 15 minutes

1. **Broker (4 minutes).** In Advisor business, show $3,819.04 in original
   invoices, plus a $106.92 debit and less a $106.92 credit. Open Alder's
   invoice from Statements to explain the dated calculation, then open Earnings
   to distinguish approval from confirmed payout. Switch to Harbor RIA to show
   the same experience. Agreements includes the public Savvy disclosures.
2. **Internal Product (4 minutes).** Start your own demo from the workspace bar.
   Switch Demo identity to Internal Product. Open the policy comparison, keep
   Alder household and October selected, and change Planning's service amount
   from $50 to $65. Give the policy a name and reason, then choose Save and
   compare. The queue shows $1,069.18 before and $1,084.18 after. Open Data lineage
   to inspect the source record, assignment and calculation that feed this path.
3. **Internal Finance (4 minutes).** Choose Harbor RIA and open Recognition in
   Finance. Follow the original $250 bill and its $90 credit to $160 net billed,
   $125 confirmed cash and $35 outstanding. See the mock journal and supplied
   schedule. Use September to show the $50 credit and $20 confirmed refund.
4. **Architecture (3 minutes).** Show the mental model, then Components and
   Billing engine. Open Alder or Harbor to connect the diagram to an executed
   billing subject. The main workspace overview totals the book.

## Questions for the discussion

- Brokers: can you explain an invoice, adjustment or payout without asking Finance?
- Product: do the data lineage, policy lifecycle and single engine fit Savvy's model?
- Finance: are native claims, cash matching and recognition clearly separated, and
  what fields would Campfire need in the handoff?

## Scope to state once

This is an independent prototype with fictional records and separate visitor workspaces.
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
Start again closes only your visitor workspace and returns to the prepared samples.
Use the [Finance acceptance worksheet](FINANCE-ACCEPTANCE.md) to record sign-off.
