# Evidence, requirements and prototype scope

> Continuation note (13 November 2026): the local build has resumed. See [current implementation status](CONTINUATION-STATUS.md) and [validation](VALIDATION-CONTINUATION.md). Planning and earlier prototype descriptions below are historical; publication remains paused.

Status: evidence review in progress. This is an independent synthetic prototype, not Savvy's product or an integration. The publication and broader build remain paused pending the owner's direction.

## What was described in the invitation

The invitation describes advisor revenue-share arrangements with a simple 80/20 example and more complex possible arrangements involving rent, support wages, marketing and loan repayment. It says Savvy has daily data on advisors' client assets including market movement, new clients and lost clients; advisors seek an estimate of a future share payment; current calculations occur retrospectively after billing and involve spreadsheets and manual math. It offered access to a staging environment and real code/data for a work trial. The invitation is context, not proof of private schema, policy implementation, production data, access or authorization for this independent demo.

## Public information and supplied context

Savvy publicly describes an advisor platform above the custodian layer and a multi-custodian approach. Public statements do not establish its internal database fields, interfaces, ownership, refresh times or exact client-to-advisor mappings. Public client fee disclosures are client billing terms, not proof of advisor compensation policy. Links and retrieval context are in `SOURCE-REGISTER.json` and `RESEARCH-SAVVY.md`.

The project owner says Savvy uses Campfire. We have not independently verified the relationship, tenant configuration, records, API access or whether any particular accounting workflow applies. There is no live connection.

## Owner-directed product requirements, not established Savvy contract facts

- Baseline broker/advisor split, with standard and effective-dated promotional terms; more granular matching terms override higher-level rates. Equally specific conflicts require a defined priority or review.
- Prepurchased arrangements in either direction: Savvy may prepay a broker or the broker may prepay Savvy. Show billing value separately from additional cash and apply zero incremental cash only to valid covered amounts. Mechanism, coverage units, settlement and recovery terms need agreement-specific definition.
- Post-hoc guarantees configurable by approved measures, dimensions, grouping and periods; distinguish a floor from a ceiling and do not mix units without a defined conversion.
- Policies should be changeable by authorized users without code changes for supported mechanisms, after validation and approval. Arbitrary new mechanisms or data sources may still need engineering.
- Client-specific legal wording linked to structured terms and reusable reviewable clause components. No automated legal approval or execution.
- Prefer Savvy-owned internal sources and classifications; do not require a new broker-provided feed. Do not assume a particular internal source, segmentation, delivery or controlled classification exists.

These are requested capabilities and illustrative scenarios. They do not establish that Savvy currently has, uses or needs a given clause, segment, workflow or policy.

## Existing implementation as of this review

- The earlier advisor dashboard is a synthetic example for daily closing billable AUM, ACT/365 and monthly arrears; its fictional expense, loan, split, collection and payout assumptions are not established Savvy terms. No live data or posting.
- `commercial_reporting` is a separate local Python/SQLite experiment. It supports a fixed period fee, a percentage of an explicitly supplied basis, raw input retention, explicit versioned clauses and sample invoice/credit/cash observation batches. It is not connected to the dashboard.
- Neither part implements the requested full baseline/promotion/override hierarchy, bidirectional prepurchases and settlement, configurable dimensional guarantees, legal review workflow, or a Savvy-owned daily feed.
- A dated explicit `project` call is not an automated daily schedule; actual events are supplied synthetic examples, not reconciled source-of-truth billing or payout events.
- The local Git repository is a standalone working copy; it is not a newly published GitHub repository. The Site record is private and unpublished. Do not imply otherwise.

## Unknowns that require discovery

Which internal source supplies asset information; source grain, completeness and update schedule; how advisors, accounts and relationships are assigned; whether particular dimensions are controlled by Savvy; whether data includes flows or market attribution; eligible fee and compensation bases; actual agreement terms; allocation and rounding; settlement; and how billing, ERP and payout records relate. No external feed is required for the synthetic demonstration; no public schema establishes Savvy's internal format.

## Next work

Continue evidence review and request a sanitized data sample plus finance-approved historical example if the opportunity supports that. Keep user-requested capabilities as testable hypotheses and clearly distinguish implemented from planned. Do not interpret unapproved dimensions or contract wording as executable facts. Do not publish or share the demo while the owner's publication pause remains in place.
