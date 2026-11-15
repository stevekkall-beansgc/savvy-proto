# Savvy branding and recorded settlement milestone

13 November 2026. This extends the local synthetic prototype; it does not connect
to Savvy or Campfire, send payments, post accounting entries or execute contracts.

## Visual reference

The owner directed the public Savvy site as the reference. The unchanged official
white wordmark, ABC Diatype controls, Big Caslon headings, dark green, gold,
ecru and warm neutral palette now replace the earlier Legume treatment.
`SAVVY-BRAND-REFERENCE.md` records exact official URLs and token values. No private
style guide or internal product library was available or implied.

## New behavior

The Settlement desk shows approved fictional obligations and directional grants.
It is separate from the current projection's fee observations: these are small,
independent worked settlement cases, not asserted company earnings or obligations.

- Finance can record positive monetary coverage against a compatible obligation.
  The source opening remains immutable. Net applications cannot exceed either the
  grant opening or the obligation amount. Both directions are tracked separately.
- A reversal appends a new entry referencing the original application. It restores
  that exact grant and obligation once, without deleting original evidence.
- Applications and reversals use one PostgreSQL scope lock plus transactional
  idempotency. Scoped foreign keys and a unique original reversal reference protect
  identity and duplicate reversal behavior. These are local application controls,
  not a claim of a production tamper-proof ledger.
- A new projection copies the known source snapshot and incorporates recorded
  grant entries through its declared knowledge cutoff and business date. The
  derived opening and entry manifest are frozen with the result. Projections never
  create ledger entries or spend/reserve actual coverage.
- Established grant openings cannot be reset by importing a differently valued
  snapshot. The original source snapshot's `remaining_minor` is its supplied
  opening; recorded entries are applied once in the derived projection input.

Collections now retains receipt revisions and original match history. Finance
can reverse an internal match while retaining observed cash, or record a synthetic
receipt-source reversal that releases its internal matches. The receipt ID stays
the same and the revision advances. Prior receipt and match evidence remains.

`collections(knowledgeCutoff:)` reconstructs evidence known at an earlier time.
A source reversal supplies a “View before reversal” link; a causally later
microsecond timestamp ensures an immediate reversal still has a valid prior view.
No reversal is proof of a bank refund. Invoice application, bank settlement,
accounting AR and revenue recognition remain null without their own evidence.

## Worked cases

- Two $600 claims against one $1,000 advance cannot both be applied in full.
  After one $600 application, at most $400 remains. A projection does not reserve
  either amount. Reversing the first application restores exactly $600 once.
- Broker prepurchase $750 against a $1,000 firm-directed service obligation leaves
  $250 uncovered; the full obligation remains $1,000. It cannot be netted into the
  opposite-direction advisor advance.
- A separate $1,500 advisor advance can cover a $1,000 compatible obligation,
  leaving $500. Only grants explicitly present in the projection's source manifest
  participate in that projection; other worked cases are not silently added.
- A source receipt $600 matched to a $1,000 customer charge can be reversed locally.
  Current active receipts/matches become $0 and unmatched charge $1,000; the prior
  as-known view still shows $600 matched and $400 unmatched. An independently linked
  invoice remains a separate object; no cash or recognition event is fabricated.

## Reporting and contract

GraphQL contract 0.3.0 adds entitlementLedger, CONSUME_ENTITLEMENT,
REVERSE_ENTITLEMENT, REVERSE_MATCH, REVERSE_RECEIPT and the collections cutoff.
Money is still exact USD cents serialized as strings at the API boundary.
Only the simulated Finance role may write recorded settlement or reversal entries.
The advisor role can inspect only its own grants and customer evidence.

The dbt project now has nine models and 29 tests, including signed entitlement
entries, reconciled grant balances and original match/reversal history. Active
matching models exclude reversed applications. Customer cash context uses the
latest receipt revision; a known reversal can produce an evidenced zero, while
missing receipt evidence remains null. No model posts or changes source tables.

## Limits and next work

USD, monetary grants and exact full-original reversals only; no FX, interest,
partial reversals, expiring-entry adjustments, new grant authoring UI, general
obligation authoring, automatic actualization of projections, real cash movement,
accounting posting, closed-period policy or production authentication.

The supplied demo uses 13 November 2026 and the fixed 18:00 ET projection cutoff.
The API accepts another explicit ISO knowledge cutoff for a projection. Events
recorded after a cutoff do not rewrite its results; a later-cutoff run is needed.
Legal/Finance example review continues to use the declared demo reference cutoff.

Next bounded development: independent invoice-application and bank-settlement
proof, gross-to-net fee bridge, closed-period late corrections, then the separate
Ruby Campfire offline accounting lifecycle. Full S01–S30 completion is not claimed.
