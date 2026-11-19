#!/usr/bin/env python3
"""Build the self-contained architecture walkthrough from verified source refs."""
from pathlib import Path
from hashlib import sha256
from datetime import datetime, timezone
import base64
import json
import subprocess
import re
import argparse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
API = 'apps/api/app/'
SERVICE = API + 'services/'
ENGINE = API + 'domains/economics/'
COMPONENTS = {}


def ref(path, needle, label):
    lines = (ROOT / path).read_text().splitlines()
    hits = [i for i, line in enumerate(lines, 1) if needle in line]
    if not hits:
        raise ValueError(f'Missing source target: {path}: {needle}')
    start = hits[0]
    return dict(path=path, line=start, label=label,
                excerpt='\n'.join(lines[start-1:start+15]),
                sha256=sha256((ROOT / path).read_bytes()).hexdigest())


def add(key, title, technology, status, summary, implementation, contract, limit, refs=()):
    COMPONENTS[key] = dict(id=key, title=title, technology=technology, status=status,
                           summary=summary, implementation=implementation,
                           contract=contract, limit=limit, refs=list(refs))


add('raw', 'Source payloads', 'JSON files and API events', 'Bounded',
    'Balances, holdings, dates, reported rates and cash observations enter as source records. One-time commercial requests use a governed event path.',
    'The current fixture inputs are JSON. The household fixture contains original observations, dated memberships and fictional terms. Provider-specific file, webhook and API connectors still need to be built.',
    ['Input: original payload plus source identity and revision.', 'Output: original bytes submitted to ingestion.', 'Retain source fields even when the payload cannot be normalized.'],
    'No live network, custodial or bank feeds are connected.',
    [ref('fixtures/disclosures/household.json', '"observations"', 'Household source observations'), ref(SERVICE+'medallion_workbench.rb', 'def ingest_delivery', 'Current delivery entry point')])
add('ingest', 'Source adapter and parser', 'Custom Ruby inside Rails', 'Bounded',
    'Capture the delivery before interpreting it. A rejected or duplicate delivery remains an arrival record.',
    'MedallionWorkbench#ingest_delivery retains original bytes, calculates SHA-256, parses JSON, validates an allowlisted envelope and detects source/revision conflicts. Parsing and fixture normalization currently share this method; there is no separate connector product.',
    ['Input: bounded synthetic JSON, source ID and revision.', 'Output: artifact + delivery classification; accepted fact revisions.', 'Idempotency and database transactions protect retry behavior.'],
    'Known fixture fields only. Production needs one source adapter per provider and versioned schema mappings.',
    [ref(SERVICE+'medallion_workbench.rb', 'def ingest_delivery', 'Capture, parse and classify'), ref(SERVICE+'workbench.rb', 'def operate(', 'Transactional command and idempotency boundary')])
add('bronze', 'Bronze: retained originals', 'PostgreSQL bytea + JSONB', 'Implemented',
    'Bronze is an immutable source history, not a cleaned copy of the latest file.',
    'MedallionEvidence retains artifact bytes, hashes, arrival records and revisions. Rails makes persisted records read-only and PostgreSQL triggers reject updates and deletes.',
    ['Original bytes and each arrival remain addressable.', 'Accepted, rejected and duplicate outcomes keep provenance.', 'Corrections append a new revision.'],
    'The prototype stores bytes in PostgreSQL. External object storage is planned.',
    [ref(API+'models/medallion_evidence.rb', 'class MedallionEvidence', 'Append-only Rails model'), ref('apps/api/db/structure.sql', 'CREATE TABLE public.medallion_evidence', 'Artifact, revision and payload storage'), ref('apps/api/db/structure.sql', 'CREATE TRIGGER medallion_no_update_delete', 'Database immutability trigger')])
add('normalize', 'Normalizer', 'Ruby validation and selection services', 'Bounded',
    'Convert provider fields into scoped, typed records while preserving their source references.',
    'The current ingest method validates fixture values. DisclosureSources validates currency, identity, membership intervals, revisions and complete holding/day coverage. DisclosureWorkbench constructs engine facts in minor units. These are current responsibilities across services, not an existing class named Normalizer.',
    ['Input: original observations and source revisions.', 'Output: typed facts with units, currency, IDs and source references.', 'Missing required observations and ambiguous sources block the affected calculation.'],
    'Generic field mapping, source discovery and import administration are not implemented.',
    [ref(SERVICE+'medallion_workbench.rb', 'def ingest_delivery', 'Fixture parsing and normalization'), ref(SERVICE+'disclosure_sources.rb', 'def self.select(', 'Scoped source validation and selection'), ref(SERVICE+'disclosure_workbench.rb', 'def manifest_for(', 'Construct typed manifest facts')])
add('silver', 'Silver: records and policy bindings', 'PostgreSQL versioned records', 'Implemented',
    'Silver connects normalized observations to the exact commercial policy applicable to the run.',
    'Scoped fact, membership, policy and assignment records are retained with revisions and effective/recorded dates. Manifest construction selects a dated assignment and source revisions; the engine evaluates policy predicates and monetary eligibility effects.',
    ['Source observations remain separate from negotiated rates.', 'Service dates select applicability; knowledge cutoff controls what was known.', 'Membership and allocation scope are explicit.'],
    'Fixture periods and rosters are bounded. Advisor parent-child hierarchy is deferred.',
    [ref(SERVICE+'disclosure_sources.rb', 'def self.memberships!', 'Dated group membership'), ref(SERVICE+'disclosure_workbench.rb', 'def manifest_for(', 'Selected inputs and policy assignment'), ref('apps/api/db/structure.sql', 'CREATE TABLE public.commercial_rates', 'Shared commercial rate table')])
add('policy', 'Policy API and review lifecycle', 'Rails / GraphQL commands', 'Bounded',
    'Commercial changes create a new policy version. An approved policy must then be assigned to a scope and service interval.',
    'DisclosureWorkbench implements save, compare, Legal/Finance review, publication and dated assignment. Reviews bind the exact policy, frozen comparison, document reference and implementation hash. The current forms expose supported fields.',
    ['Draft → frozen comparison → review → publication → dated assignment.', 'A draft comparison does not change current earnings.', 'Changed dependencies require a new review.'],
    'An unrestricted graph editor and general contract-authoring system are not implemented.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def save_policy(', 'Save versioned policy fields'), ref(SERVICE+'disclosure_workbench.rb', 'def binding_current!', 'Exact comparison/review binding'), ref(SERVICE+'disclosure_workbench.rb', 'def assign(', 'Dated policy assignment')])
add('builder', 'Policy graph construction', 'DisclosurePolicy + typed JSON nodes', 'Bounded',
    'Supported business parameters become a declarative graph of approved operators.',
    'DisclosurePolicy.build constructs the monthly household graph from API fields. It declares eligibility, annual rate, monthly factor, assessment and allocation. Alternative supported mechanisms use DisclosureAlternatives. These builders construct graphs; Economics::Program executes the arithmetic.',
    ['Commercial values and supported mechanism choices are policy data.', 'Each node declares ID, operator, unit, basis and dependencies.', 'No arbitrary Ruby, JavaScript or SQL expressions are accepted.'],
    'New parameter combinations must be supported by the builder. New operator semantics require a reviewed engine change.',
    [ref(SERVICE+'disclosure_policy.rb', 'def self.build(', 'Current policy-to-graph builder'), ref(SERVICE+'disclosure_alternatives.rb', 'class DisclosureAlternatives', 'Alternative graph templates')])
add('manifest', 'Frozen input manifest', 'Rails assembly + SHA-256', 'Implemented',
    'A run reads a pinned set of source revisions and policy references, rather than querying a moving current balance while calculating.',
    'DisclosureWorkbench#manifest_for selects complete source observations and memberships, binds the assignment and records exact source revisions/hashes. Economics::Engine hashes the manifest and policy bundle and records the context in its result.',
    ['Input: approved assignment, scoped facts and knowledge cutoff.', 'Output: typed fact map + assignment and source references.', 'The manifest, policy and context define a reproducible request.'],
    'A matching ID or hash alone does not prove a valid source/payment relationship; the caller validates those links.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def manifest_for(', 'Manifest construction'), ref(ENGINE+'engine.rb', 'def evaluate(*args', 'Manifest validation and result hashes')])
add('context', 'Run context and clocks', 'Explicit API data', 'Implemented',
    'Every run is scoped to a tenant, legal entity, service interval and knowledge cutoff.',
    'Engine context prevents cross-scope evaluation and future evidence from silently entering a historical calculation. Hypothetical comparisons can use a separate policy knowledge clock while preserving the source cutoff.',
    ['Service time: when terms and services apply.', 'Knowledge time: what source revisions were known.', 'Comparison context is explicit and does not issue bills.'],
    'Prototype identities are simulated; production authentication and authorization remain to be integrated.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def engine_run(', 'Construct scoped run context'), ref(ENGINE+'engine.rb', 'def evaluate(*args', 'Scope and clock checks')])
add('engine', 'Single billing engine', 'Economics::Engine + Economics::Program', 'Implemented',
    'One deterministic interpreter executes fees, credits, compensation and balances from a versioned policy graph.',
    'Economics::Engine validates the request and adds contracts, hashes and lineage. Economics::Program evaluates the dependency graph with exact rational values. Both product models and one-time commercial items enter this interpreter; Rails services orchestrate and persist its results.',
    ['evaluate(policy_bundle:, input_manifest:, context:) → typed result.', 'Same pinned inputs, policy, context and engine version → same result.', 'A calculated obligation is distinct from an issued invoice, payment or accounting posting.'],
    'The operator language is bounded. The prototype does not support arbitrary formulas or every possible commercial contract.',
    [ref(ENGINE+'engine.rb', 'def evaluate(*args', 'Public evaluation boundary'), ref(ENGINE+'program.rb', 'def run', 'Shared interpreter execution'), ref('docs/MEDALLION-ENGINE-CONTRACT.md', '# Medallion engine contract', 'Engine contract')])
add('validation', 'Validation boundary', 'Engine contract + graph validation', 'Implemented',
    'Reject incompatible units, invalid scope, unauthorized policy, ambiguous rules and invalid graph structure before producing usable outputs.',
    'Program.validate! checks a bounded acyclic graph and operator contracts. Engine.validate adds output classes and direction checks. The outer evaluate method validates scope, source identities, policy approval and clocks. Source adapters enforce coverage and authorized relationships.',
    ['No cyclic references or unbounded execution.', 'Exact accrual, assessed money and source-reported values are distinct bases.', 'Opposing obligations cannot be hidden inside an ordinary subtraction.'],
    'Coverage and business relationship validation are shared responsibilities of the caller and engine, not graph syntax alone.',
    [ref(ENGINE+'program.rb', 'def self.validate!', 'Graph and operator validation'), ref(ENGINE+'engine.rb', 'def validate(policy:', 'Output and direction contract')])
add('program', 'Policy DAG interpreter', 'Economics::Program', 'Implemented',
    'Nodes reference other nodes. The interpreter evaluates dependencies and retains typed results for each successful node.',
    'Program#calculate recursively resolves bounded dependencies and memoizes computed values. Integer and rational inputs avoid floating-point drift. Required missing data produces blocked or partial outputs instead of an invented zero.',
    ['Operators compose; the engine does not dispatch to product-specific fee calculators.', 'Intermediate, terminal and summary node roles are explicit.', 'A parent total and its allocated child lines are not additional independent charges.'],
    'The standalone evaluate_program entry is a test/helper primitive; it does not replace the full manifest authorization boundary.',
    [ref(ENGINE+'program.rb', 'def calculate(', 'Dependency evaluation'), ref(ENGINE+'program.rb', 'def run', 'Result roles, exceptions and status')])
add('selection', 'Rate and event selection', 'select / fact / sum_facts', 'Implemented',
    'Choose dated, scoped rates and qualifying event collections from policy predicates.',
    'The shared Program selector resolves candidates using effective dates, source facts, eligibility dimensions and explicit priorities. sum_facts selects approved event collections within the declared period and retains every selected source reference.',
    ['Standard, promotion and targeted promotion share one commercial rate store.', 'Future, out-of-period and nonmatching events do not enter the selected collection.', 'Conflicting equally ranked candidates raise a rule conflict.'],
    'Missing signup dates or ambiguous mappings must be resolved; the engine does not guess.',
    [ref(ENGINE+'program.rb', 'def self.choose_rate', 'Shared selection primitive'), ref(ENGINE+'program.rb', "when 'sum_facts'", 'Event collection contract'), ref(SERVICE+'product_workspace.rb', 'def validate_rates!', 'Commercial rate validation')])
add('pricing', 'Rates, tiers and accrual', 'multiply / bands / accrue', 'Implemented',
    'Compose percentage, fixed, hourly and tiered economics using typed arithmetic and explicit time factors.',
    'bands applies progressive slices; multiply composes scalars and amounts; accrue converts a source-reported basis to exact accrual. The monthly fixture builds an annual rate × 1/12 factor as policy nodes. Service quantities and time factors must be explicit inputs or policy values.',
    ['Amounts stay exact until an assessment node.', 'Daily source coverage is validated before average-daily policies run.', 'Refresh grain, accrual grain and billing cadence are separate decisions.'],
    'The engine does not independently choose a valuation convention or accounting treatment.',
    [ref(ENGINE+'program.rb', "when 'multiply', 'accrue'", 'Exact multiplication and accrual'), ref(ENGINE+'program.rb', "when 'bands'", 'Progressive band contract'), ref(SERVICE+'disclosure_policy.rb', "node.call('month_factor'", 'Monthly factor in policy data')])
add('limits', 'Caps, floors and guarantees', 'min / max / add / subtract', 'Implemented',
    'Caps and floors are ordinary policy graph compositions, with explicitly declared inputs and units.',
    'The household minimum uses max(assessed fee, minimum). Other graph compositions support guarantees and offsets without a product-specific calculator. Dependency selection determines which outputs contribute to the base.',
    ['Compatible units and monetary bases are required.', 'Guarantees cannot recursively include themselves.', 'Coverage and opposing-party offsets require separately valid relationships.'],
    'A configured field is only supported when its complete graph and validation path are implemented.',
    [ref(SERVICE+'disclosure_policy.rb', "node.call('minimum_applied'", 'Minimum fee composition'), ref(ENGINE+'program.rb', "when 'add', 'min', 'max'", 'Compatible typed aggregation')])
add('allocation', 'Assessment and allocation', 'assess / allocate_by / distribute', 'Implemented',
    'Round explicitly, then allocate an assessed amount while preserving the total exactly.',
    'assess uses declared half-up rounding. allocate_by reads exact referenced weights and applies largest remainder with a stable recipient-ID tie break. Negative allocations preserve the input sign; invalid or zero total weights are rejected.',
    ['$1,000 total → $600 account A + $400 account B.', 'The allocation is the same charge split across accounts.', 'Original charge and child allocations must not be added together.'],
    'Policy controls where assessment occurs. A report must not independently reround or reprice the result.',
    [ref(ENGINE+'program.rb', 'def proportional_allocation', 'Conserved allocation algorithm'), ref(ENGINE+'program.rb', "when 'allocate_by'", 'Referenced allocation weights'), ref(ENGINE+'program.rb', "when 'assess'", 'Explicit assessment contract')])
add('netting', 'Authorized netting', 'net + authority fact', 'Implemented',
    'Net opposing obligations only when an effective authorization explicitly permits it.',
    'Engine validation rejects disguised opposing-party subtraction. The net operator requires matching parties, currency, knowledge cutoff and an authority interval covering the service period.',
    ['Gross obligations remain individually addressable.', 'Netting is a separate declared output.', 'Absent authority blocks the net; independently completed obligations remain available.'],
    'Netting does not prove that cash moved or determine gross/net accounting presentation.',
    [ref(ENGINE+'engine.rb', 'def validate(policy:', 'Opposing obligation safeguards'), ref(ENGINE+'program.rb', "when 'subtract', 'net'", 'Effective netting authority')])
add('results', 'Typed result set', 'Result details + output references', 'Implemented',
    'The engine returns amounts, classifications, parties, service intervals, dependencies and source references—not just a total.',
    'Each detail declares unit, basis, role and economic identity. Monetary terminal outputs declare an output class; obligations and net balances require payer, payee and currency. Result-level hashes pin inputs and policy.',
    ['Completed, partial and blocked results are distinct.', 'Output references identify which details are consumable.', 'Lineage identifies the actual source revisions and executed dependencies.'],
    'A result can be assessed but unbilled. Issuance and settlement are separate records.',
    [ref(ENGINE+'engine.rb', 'details = result[', 'Typed result and lineage enrichment'), ref(SERVICE+'audience_read_model.rb', 'def executed_input_refs', 'Executed input references')])
add('publication', 'Result publication', 'Transactional Rails services', 'Implemented',
    'Select an exact run and output version for reporting while retaining earlier runs and publication history.',
    'DisclosureWorkbench#evaluate stores a run and a publication referencing that run. A changed assessment flags correction review; it does not silently reissue the original invoice. Reporting requires exact publication proof.',
    ['Run identity and hashes remain linked to publication.', 'A draft or unpublished retry cannot replace a published reporting result.', 'Policy publication and calculated-result publication are different events.'],
    'The current fixture publication path is synchronous; durable asynchronous workers are planned.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def evaluate(input', 'Run retention and result publication'), ref('analytics/models/marts/fct_medallion_publication.sql', 'with ', 'Published run selection and proof')])
add('gold', 'Gold: results and read models', 'PostgreSQL + SQL projections', 'Implemented',
    'Retain detailed calculated outputs and expose selected publication snapshots to the product and reporting layers.',
    'Engine results are stored in append-only run records. SQL projections select exact publication versions and output classes. Audience read models provide compact, scoped summaries and paged record drilldowns.',
    ['Detailed result remains the source of each reported amount.', 'Hourly/daily snapshots are not extra amounts to sum across time.', 'Native billing objects have their own issuance and lifecycle records.'],
    'The prototype uses one PostgreSQL database; medallion names are logical domains, not separate database products.',
    [ref('analytics/models/marts/fct_medallion_result_detail.sql', 'select ', 'Detailed engine result projection'), ref(SERVICE+'audience_read_model.rb', 'def summary(', 'Published audience summary')])
add('billing', 'Native billing objects', 'Rails + billing_* tables', 'Bounded',
    'Savvy owns obligations, invoices, invoice lines and instructions close to its commercial data.',
    'The fixture issuance path consumes exact engine output identities and creates linked native objects in transactions. BillingCatalog validates persisted objects and conservation. A new assessment flags an explicit billing correction instead of editing a historical invoice.',
    ['Calculation → explicit issuance → invoice + lines + obligations.', 'Line service dates and issue/due dates are separate.', 'Cash application and accounting treatment reference the billing objects.'],
    'General production issuance workflows and live custodian instructions are not implemented; fixture issuance is bounded.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def bootstrap(input', 'Fixture calculation and native issuance'), ref(SERVICE+'billing_catalog.rb', 'def validate_conservation!', 'Billing conservation checks'), ref('apps/api/db/structure.sql', 'CREATE TABLE public.billing_invoice_lines', 'Native line schema')])
add('events', 'One-time commercial events', 'Governed Rails event register', 'Bounded',
    'One-time charges, credits and compensation are approved inputs to the same engine, not manual edits to statement totals.',
    'Submit and review retain event versions and exact approval references. Evaluation checks that the selected policy declares the event treatment and includes eligible approved events through sum_facts. Payout requests remain distinct from confirmed payment records.',
    ['Request → review → approved event → same engine → classified output.', 'Post-hoc corrections append new records.', 'A cash observation enters the independent cash path.'],
    'Event kinds and combinations are currently allowlisted. No live payout execution is provided.',
    [ref(SERVICE+'medallion_workbench.rb', 'def submit_event(', 'One-time event submission'), ref(SERVICE+'medallion_workbench.rb', 'def review_event(', 'Version-bound event review'), ref(SERVICE+'medallion_workbench.rb', 'def evaluate(case_id', 'Approved events enter the shared manifest')])
add('cash', 'Independent cash matching', 'Rails cash and refund services', 'Bounded',
    'Receipts, refunds and payouts are confirmed source observations linked to obligations through separate application records.',
    'MedallionWorkbench records and applies confirmed payments. DisclosureRefunds validates credit and original-receipt linkage and prevents over-application. FinanceTiming handles scoped associations and reversals.',
    ['$500 commercial credit is distinct from a $300 confirmed refund.', '$200 remains owed in the retained sample.', 'A payment request or billing instruction is not confirmed cash.'],
    'No bank, custodian or payment execution is connected.',
    [ref(SERVICE+'medallion_workbench.rb', 'def record_payment(', 'Record independent payment observation'), ref(SERVICE+'disclosure_refunds.rb', 'def self.validate!', 'Refund relationship and remaining bounds'), ref(SERVICE+'finance_timing.rb', 'def associate(', 'Scoped cash association')])
add('recognition', 'Revenue recognition records', 'Supplied accounting treatment and outcomes', 'Mocked',
    'Commercial amounts, recognition schedules and posted accounting outcomes remain separate records.',
    'FinanceTiming and the disclosure workspace retain supplied schedules and mock reported postings. The UI shows scheduled, reported and missing amounts without choosing accounting policy from an invoice or cash receipt.',
    ['Billing objects provide commercial inputs.', 'Approved accounting treatment supplies recognition timing.', 'A reported posting is independently recorded; a missing posting remains missing.'],
    'No automatic accounting-policy selection or live journal posting is implemented.',
    [ref(SERVICE+'finance_timing.rb', 'def mock_acknowledge(', 'Mock accounting acknowledgment'), ref(SERVICE+'disclosure_workbench.rb', 'def bootstrap_lifecycle(', 'Separate lifecycle and accounting records')])
add('clm', 'CLM adapter', 'Mock document / review references', 'Mocked',
    'Link agreed terms and legal review to the exact policy version before activation.',
    'Current review records bind document references, comparison hashes and policy hashes. The actual agreement registry is empty. Public ADV/CRS disclosures remain disclosures, not signed agreements.',
    ['Legal document/version → policy proposal → bound review.', 'Changed terms invalidate the previous approval binding.', 'The source document does not directly execute pricing.'],
    'No CLM vendor connector, signature or real agreement has been supplied.',
    [ref(SERVICE+'disclosure_workbench.rb', 'def binding_current!', 'Policy/document/comparison binding'), ref('docs/DISCLOSURE-BACKEND-NOTES.md', 'Campfire and CLM are mocked', 'Current integration limits')])
add('campfire', 'Campfire adapter', 'Mock accounting integration', 'Mocked',
    'Translate Savvy-owned commercial records into accounting inputs and retain supplied outcomes separately.',
    'The current Finance workflows keep treatment, schedules and mock acknowledgments separate from invoices and confirmed cash. Live integration would use explicit external IDs, idempotent delivery and independently returned posting references.',
    ['Savvy retains billing ownership.', 'Accounting recognition and posting remain separate from fee evaluation.', 'Missing acknowledgment does not become a posted journal.'],
    'No live Campfire tenant or API connection is configured.',
    [ref(SERVICE+'finance_timing.rb', 'def mock_acknowledge(', 'Mock integration boundary'), ref('docs/DISCLOSURE-BACKEND-NOTES.md', 'Fictional recognition input', 'Supplied accounting scope')])
add('postgres', 'Shared PostgreSQL database', 'PostgreSQL 17 + Rails Active Record', 'Implemented',
    'One operational database stores the logical medallion stages, policy history, billing objects and cash/accounting records.',
    'The authoritative SQL schema declares exact money, scoped identities, foreign keys, uniqueness and append-only triggers. MedallionEvidence stores versioned JSONB records; native billing tables preserve structured invoice and obligation relationships.',
    ['Bronze: original bytes and arrival metadata.', 'Silver: facts, policy versions, memberships and assignments.', 'Gold: run details, publication references and native billing records.'],
    'Production tenancy, backup/restore, access control and capacity require deployment-specific validation.',
    [ref('apps/api/db/structure.sql', 'CREATE TABLE public.medallion_evidence', 'Medallion storage'), ref('apps/api/db/structure.sql', 'CREATE TABLE public.billing_invoices', 'Native invoice storage'), ref('compose.medallion.yaml', 'image: postgres:', 'Local PostgreSQL runtime')])
add('reporting', 'Reporting transformations', 'dbt + PostgreSQL SQL models', 'Implemented',
    'Project selected engine results into hourly/daily reporting snapshots without executing commercial policy again.',
    'dbt joins exact published run identities to typed result details and retains source lineage and aggregation semantics. A total, its account allocations and a later snapshot cannot be summed as independent earnings.',
    ['Read stored results and publication proof.', 'Select exact detail and output roles.', 'Aggregate only where the declared semantics allow it.'],
    'dbt is our reporting choice; Savvy usage has not been verified. No additional pricing engine is introduced.',
    [ref('analytics/models/marts/fct_medallion_rollup.sql', '-- Selected component snapshots', 'Hourly/daily snapshot projection'), ref('analytics/tests/medallion_rollup_semantics.sql', 'select ', 'Reporting semantics checks')])
add('graphql', 'Product API', 'Rails + GraphQL Ruby', 'Implemented',
    'Serve scoped read models and explicit commands to the three audience experiences.',
    'The Rails controller builds a request context and executes WorkbenchSchema. Query fields read retained projections; mutations use authorized command services. The Next.js proxy reads the visitor cookie and passes its token to Rails. DemoSession maps its hash to a fresh PostgreSQL scope. Public sample queries read the reference workspace. Commands require an active visitor scope.',
    ['Client: terms, statements and account drilldown.', 'Product: policies, comparisons and lineage.', 'Finance: obligations, cash matching and recognition records.'],
    'Visitor scopes are fictional and expire after 24 hours. Start again closes the current scope and returns to the reference examples. Demo role switches are separate from workspace isolation.',
    [ref(API+'controllers/graphql_controller.rb', 'def execute', 'API request boundary'), ref(API+'graphql/workbench_schema.rb', 'class WorkbenchSchema', 'GraphQL schema'), ref('apps/web/app/api/graphql/route.ts', 'export async function POST', 'Next.js API forwarding'), ref(SERVICE+'demo_session.rb', 'def start', 'Private synthetic workspace provisioning')])
add('ui', 'Three audience interfaces', 'Next.js + React + TypeScript', 'Implemented',
    'Clients, Product and Finance use the same retained amounts through audience-specific read models.',
    'The current app shares navigation for affiliated advisors and independent RIAs. It provides book-level summaries and client drilldown, contextual policy workflows, source lineage, cash matching and supplied recognition views.',
    ['No browser fee calculator.', 'Source and architecture details remain internal.', 'Statements use conventional invoice-style rows and dates.'],
    'Advisor account parent-child relationships remain deferred.',
    [ref('apps/web/app/page.tsx', 'export default function Page', 'Audience shell'), ref('apps/web/app/DisclosureWorkspace.tsx', 'export default', 'Disclosure-informed UI'), ref(SERVICE+'audience_read_model.rb', 'def summary(', 'Shared published read projection')])
add('queue', 'Durable background processing', 'Rails jobs + queue backend to select', 'Planned',
    'Run ingestion, normalization, evaluation and publication as durable jobs with explicit retry and status records.',
    'The current prototype runs commands synchronously. A production worker would call the same services with tenant, entity, source revisions, policy version and idempotency key. Backend selection should follow Savvy’s actual deployment conventions.',
    ['Durable queue → job worker → existing service.', 'Retries reuse the same input identity.', 'Failures remain inspectable and can be retried without duplicate billing.'],
    'There is no deployed queue worker in this prototype. The linked plan describes the required job contracts.',
    [ref('docs/TECHNICAL-SPECIFICATION.md', '- Rails jobs:', 'Planned worker contracts'), ref(SERVICE+'workbench.rb', 'def operate(', 'Existing idempotent service boundary')])
add('objectstore', 'Object storage', 'Immutable file storage backend to select', 'Planned',
    'Move large original files to immutable object storage while keeping artifact hashes and version references in PostgreSQL.',
    'Original bytes are currently PostgreSQL bytea. A future adapter would write the immutable object, record its version and hash, and retain arrival metadata in the same ingestion contract.',
    ['Store original bytes without normalization.', 'Reference immutable object version + SHA-256.', 'Support retention and reprocessing without overwriting originals.'],
    'No object-storage bucket, vendor or cost commitment is introduced.',
    [ref('apps/api/db/structure.sql', 'original_bytes bytea', 'Current original-byte storage'), ref(SERVICE+'medallion_workbench.rb', 'def ingest_delivery', 'Current capture contract')])
add('agents', 'Assistive agents', 'API clients; implementation pending', 'Planned',
    'Agents can suggest mappings, draft supported policy changes and investigate unexplained results through the same APIs.',
    'No autonomous runtime agent is deployed. Proposed agents would submit reviewable requests and read deterministic traces; adapters, source selection, calculations and publication remain deterministic services.',
    ['Ingestion: mapping and missing-delivery suggestions.', 'Product: policy proposals and frozen impact explanations.', 'Finance: match suggestions and posting-gap investigation.'],
    'Agents cannot set calculated amounts, activate policies without required review, execute payments or post journals.',
    [ref('docs/MEDALLION-ENGINE-CONTRACT.md', 'The surrounding pipeline', 'Authority remains in deterministic services')])
add('lineage', 'Record and execution lineage', 'Rails read model + engine dependency references', 'Implemented',
    'Trace a displayed amount to an exact run, executed graph node, source revision and original payload.',
    'AudienceReadModel distinguishes recorded links from proven execution. Exact identity/revision/hash and actual interpreter bindings are required before a source-to-result edge is shown as executed.',
    ['A conceptual architecture arrow is not proof of execution.', 'Unused manifest inputs are not shown as consumed.', 'Corrections retain the previous result and its original input references.'],
    'This walkthrough explains responsibilities. Its sample graph uses the retained sample run; conceptual diagrams are not new execution evidence.',
    [ref(SERVICE+'audience_read_model.rb', 'def executed_input_refs', 'Executed binding proof'), ref(SERVICE+'audience_read_model.rb', 'def lineage_record(', 'Source-to-result lineage read')])


# Current shared implementation; retained household traces below remain historical examples.
updates={
 'raw':('Original source deliveries','BillingPipeline receives original JSON, NDJSON or base64 bytes. Fields are retained before mapping or validation. Source mappings and normalization executions are versioned. No live provider connector is connected.','billing_pipeline.rb','def ingest('),
 'ingest':('Source adapter','BillingPipeline#ingest retains a bytea artifact and arrival with SHA-256 before invoking BillingNormalizeJob. Versioned JSON path mappings and exact conversion rules are API configuration. Duplicate and contradictory deliveries retain distinct classifications.','billing_pipeline.rb','def ingest('),
 'normalize':('Normalizer','BillingNormalizeJob calls BillingPipeline#normalize inside the scoped writer transaction. Versioned field paths, constants and exact coercions produce canonical records. A malformed row quarantines the whole delivery; replay creates a new execution without rewriting originals.','billing_pipeline.rb','def normalize('),
 'silver':('Silver: typed records and assignments','BillingPipeline selects the latest known source revision before service-date filtering. Withdrawals and active mapping versions are enforced. BillingPlatform retains dated reviewed policy schedules; account membership and daily or ending balance completeness are checked before evaluation.','billing_pipeline.rb','def manifest('),
 'policy':('Policy API and review lifecycle','BillingPlatform commands save a composable specification or typed graph, compare frozen inputs, retain independent Legal and Finance mock CLM reviews, publish and assign dated schedules. Changed sources or implementation invalidate approvals. All supported commercial changes are API data.','billing_platform.rb','def save_policy('),
 'builder':('Policy graph construction','BillingPolicy compiles AUM, progressive bands, dated standard/promotion/targeted rates, fixed, usage, time, approved events, caps and floors into one typed graph. A validated primitive graph is also accepted. Components compose; no per-product pricing implementation executes money.','billing_policy.rb','def compile'),
 'manifest':('Frozen input manifest','BillingPipeline#manifest binds exact normalized database record IDs, source revisions, mapping hashes, dated memberships and typed facts. BillingPlatform splits assignment boundaries and calls the same engine for each segment and the rollup. Missing mandatory evidence blocks invoice issue.','billing_pipeline.rb','def manifest('),
 'billing':('Native invoices and corrections','BillingDocuments issues native invoice/line/obligation records from fresh engine outputs. Finance approves an exact correction proposal against the last issued target. Atomic credit/debit notes support reallocations and repeat corrections; database guards preserve original history.','billing_documents.rb','def propose('),
 'lineage':('Record and execution lineage','BillingWorkspace reads retained deliveries, execution receipts, exact normalized revisions, frozen manifests, policies, outputs and native documents. Opening an old input resolves its exact database record, rather than the newest revision. Reads never seed or calculate.','billing_workspace.rb','def detail('),
}
for key,(title,implementation,path,needle) in updates.items():
    current=COMPONENTS[key]
    current.update(title=title,implementation=implementation,status='Implemented',refs=[ref(SERVICE+path,needle,'Shared implementation')])
    current['limit']='Synthetic local preview. Provider connectors, production identity and advisor hierarchy remain deferred; Campfire and CLM are mocked.'
COMPONENTS['ingest']['technology']='BillingPipeline · Ruby on Rails'
COMPONENTS['normalize']['technology']='BillingNormalizeJob · ActiveJob'
COMPONENTS['builder']['technology']='BillingPolicy · typed JSON graph'
COMPONENTS['billing']['technology']='BillingDocuments · PostgreSQL native tables'
COMPONENTS['policy']['summary']='One policy lifecycle and one engine serve both products; product-specific behavior is configuration.'
COMPONENTS['builder']['summary']='Compose supported commercial terms as API policy data or supply a validated typed graph.'
COMPONENTS['normalize']['summary']='Versioned mappings convert source fields into exact typed records; errors quarantine and remain replayable.'
COMPONENTS['billing']['summary']='Invoices, credit notes and debit notes are native Savvy records. Cash and accounting evidence remain separate.'
for component in COMPONENTS.values():
    if component['title']=='Background jobs':component['implementation']='BillingNormalizeJob is an actual ActiveJob entry point. The preview executes it inline and records every execution. A durable queue/worker deployment remains future infrastructure.'

add('queue','Durable scheduled work','PostgreSQL + ActiveJob + BillingWorker','Implemented',
    'Queued work survives a worker restart. A lease and retained attempts make retries inspectable.',
    'BillingWorker claims due billing_work_items with FOR UPDATE SKIP LOCKED, executes allowlisted ActiveJobs, records immutable work_attempt evidence and settles the lease. BillingNormalizeJob deduplicates records; BillingEvaluateJob reuses its job ID at the transactional command boundary. Quarantined input requires an explicit retry.',
    ['One-shot run_at scheduling and scoped batch evaluation.','Bounded automatic retries; expired leases are recoverable.','Mutable operational queue state is separate from immutable financial history.'],
    'Representative 200-group and crash/concurrency tests are synthetic proofs; no production throughput guarantee or live provider connector.',
    [ref(SERVICE+'billing_worker.rb','def self.perform_one','Claim, lease, retry and retained attempts'),ref(API+'jobs/billing_evaluate_job.rb','class BillingEvaluateJob','Idempotent evaluation job'),ref('apps/api/script/billing_worker.rb','until stop','Actual worker process')])
add('cash','Cash applications and refunds','BillingLifecycle + retained source evidence','Implemented',
    'Confirmed cash, an operational application and a refund request are separate records.',
    'BillingLifecycle verifies exact source identity/revision/hash, legal parties, currency, available cash and target version. Applications and reversals append history. Overpayments and excess credits remain visible; requested refunds require independently confirmed outbound cash. Canceling a request releases only its unapplied remainder.',
    ['No transfer is initiated.','Source revisions require review; old associations remain preserved.','Native claims less active applications produce the displayed balance.'],
    'Cash observations are synthetic; real payment execution stays outside this prototype.',
    [ref(SERVICE+'billing_lifecycle.rb','def apply(','Confirmed source application'),ref(SERVICE+'billing_lifecycle.rb','def request_refund','Refund reservation and request'),ref(SERVICE+'billing_lifecycle.rb','def position','Claim-grain ledger projection')])
add('recognition','Accounting packages and outcomes','BillingLifecycle + mock Campfire boundary','Mocked',
    'Send a versioned billing evidence package; validate an independently supplied schedule and journal response.',
    'The package pins native invoice/credit lines, service dates, policy references, cash position and an explicit fictional Finance treatment. Accepted responses bind the exact package/hash and reconcile supplied schedules and AR. Replacement requires the previous accepted source hash and a mock reversal journal reference.',
    ['Recognition is never inferred from an invoice or a receipt.','Unknown outcomes remain unknown.','Billing/cash changes make an older acknowledgment stale.'],
    'Campfire is mocked. No live journal is posted and no real accounting policy is selected by this prototype.',
    [ref(SERVICE+'billing_lifecycle.rb','def package(','Package native evidence'),ref(SERVICE+'billing_lifecycle.rb','def accept_accounting','Validate supplied schedule, posting and replacement')])
COMPONENTS['campfire']=dict(COMPONENTS['recognition'],id='campfire',title='Mock Campfire adapter')
add('earnings','Earnings and native payables','BillingPolicy + BillingPayables','Implemented',
    'The same engine composes issued fee share, salary, bonus and approved deductions. Approval and payment remain separate.',
    'A purpose=earnings policy has its own dated schedule. Issued fee-share outputs enter a frozen manifest as derived evidence. Native BillingInstruction/items/obligations retain approved payables and recoupment corrections. Confirmed payout applications determine what remains owed; the original instruction is immutable.',
    ['No second pricing engine.','Calculated estimate, approved entitlement and confirmed cash are distinct.','Independent Finance review precedes payable issue.'],
    'No payroll or payment integration is live. Equity valuation and real loan servicing are not implied by approved monetary inputs.',
    [ref(SERVICE+'billing_platform.rb','def billing_manifest','Issued fee-share derivation'),ref(SERVICE+'billing_payables.rb','def issue','Native payout issue and corrections'),ref(SERVICE+'billing_policy.rb','def compile','Shared policy compiler')])
add('credit','Credits and correction history','BillingDocuments + BillingLifecycle','Implemented',
    'A credit can exceed the bill. Keep a positive native credit note and an explicit remaining customer credit balance.',
    'The engine separates nonnegative service charge from excess-credit obligation. Signed allocation deltas issue native credit/debit notes against the last issued target. Standalone credit notes can later be corrected to a debit. Source, version, posting period and review checks bind each issue.',
    ['Original claims and native lines stay immutable.','Repeated corrections compare with the last issued target.','Refund requests, confirmations and reversals are independent evidence.'],
    'All cases are synthetic; real legal credit/refund authority still requires the governing agreement.',
    [ref(SERVICE+'billing_documents.rb','def propose','Exact correction proposal'),ref(SERVICE+'billing_documents.rb','def correct','Atomic credit/debit issue'),ref(SERVICE+'billing_lifecycle.rb','def cancel_refund','Cancel only unapplied request remainder')])
add('proof','Executed product examples','Retained synthetic lifecycle export','Implemented',
    'Both product examples run through the shared services and native records shown in the demo.',
    'The read-only export opens retained native claims, applications, accounting acceptance and worker receipts. It does not run a price calculation or generate a made-up statement total.',
    ['October: corrected bill, partial payment, current mock accounting package.','September: excess credit, refund request, partial independently confirmed refund.','Earnings: issued native payable and independently applied payout.'],
    'Each October card shows one billing subject. The app overview aggregates the full book. Visitor workspaces use fresh copies of the same fictional scenarios, with their own record IDs.',
    [ref('docs/architecture/lifecycle-run.json','billing-lifecycle-proof/v1','Executed proof snapshot'),ref('apps/api/script/export_billing_closure.rb','cases=%w','Read-only proof exporter'),ref(SERVICE+'billing_closure_seed.rb','def call','Explicit fixture setup through governed commands')])
COMPONENTS['builder']['implementation']='BillingPolicy compiles API components or accepts a typed primitive graph. Supported components cover daily/average-daily/ending and prior-period valuations, progressive bands, dated/targeted rates, fixed, usage, time, approved events, caps/floors, customer credits and earnings. Every monetary operation remains a node in Economics::Engine.'
COMPONENTS['builder']['refs'].append(ref(SERVICE+'disclosure_policy.rb','def self.build(','Retained minimal household graph builder'))
COMPONENTS['billing']['summary']='Savvy owns native invoices, credit/debit notes, obligations and payout instructions; the displayed statement is a read projection.'
COMPONENTS['billing']['refs'].append(ref(SERVICE+'billing_payables.rb','def persist','Native payable instruction and obligation persistence'))
COMPONENTS['events']['implementation']='Original one-time charge, credit, bonus, expense, advance, loan-repayment and payout inputs enter BillingPipeline as source events. Finance reviews the exact normalized revision before the same engine can consume it. Category labels do not create a second calculator.'
COMPONENTS['events']['refs']=[ref(SERVICE+'billing_platform.rb','def review_event','Exact source-bound Finance approval'),ref(SERVICE+'billing_pipeline.rb','def canonical!','Canonical event validation')]
COMPONENTS['events']['limit']='Only approved source revisions enter calculations. Cash movements and recognition are separate evidence.'
COMPONENTS['ui']['implementation']='BillingPlatformWorkspace and BillingLedger expose the shared client, Product and Finance paths. Grouped clients drill into accounts; statements open native documents; Finance opens cash/refund and mock recognition evidence; earnings separate calculated, approved and paid amounts. Reads do not price or seed.'
COMPONENTS['ui']['refs']=[ref('apps/web/app/BillingPlatformWorkspace.tsx','export default function','Shared three-audience workspace'),ref('apps/web/app/BillingLedger.tsx','export default function','Cash, recognition and earnings explanation')]
COMPONENTS['publication']['title']='Explicit issue boundary'
COMPONENTS['publication']['implementation']='BillingPlatform retains internal engine calculations. Client billing and earnings come from explicitly issued native claims and payables. Source-fresh results and the required exact independent reviews gate issue; a page read cannot publish a new amount.'
COMPONENTS['publication']['refs']=[ref(SERVICE+'billing_documents.rb','def issue(','Fresh native invoice issue'),ref(SERVICE+'billing_payables.rb','def issue','Reviewed payable issue')]
COMPONENTS['publication']['limit']='Evaluation and issuance are separate commands. No issue action executes cash or posts a live journal.'
COMPONENTS['normalize']['implementation']='BillingNormalizeJob calls BillingPipeline#normalize under the scoped transactional writer lock. It can run immediately or through the PostgreSQL queue. Versioned mappings preserve originals, exact conversions and source revisions; a failed row quarantines the delivery.'
COMPONENTS['normalize']['refs']=[ref(API+'jobs/billing_normalize_job.rb','def perform','Actual normalization job'),ref(SERVICE+'billing_pipeline.rb','def normalize','Versioned normalization and quarantine')]
COMPONENTS['reporting']['implementation']='dbt projects native invoices/lines, signed corrections, daily engine accruals, claim balances, cash lineage and mock accounting evidence at their explicit grains. These are read-only projections, not an additional pricing or recognition engine.'
COMPONENTS['reporting']['refs']=[ref('analytics/models/marts/fct_shared_claim_balance.sql','with claims','Native claim and cash balance projection'),ref('analytics/models/marts/fct_shared_mock_accounting.sql','select tenant_id','Independent mock accounting outcomes')]

def build(source_commit=None):
    sample_path = HERE / 'sample-run.json'
    sample = json.loads(sample_path.read_text())
    source_map = HERE / 'source-map.json'
    pinned = json.loads(source_map.read_text())['source_commit'] if source_map.exists() else '3ce278bb727e333e30b2fcd4eed1be84337b2eeb'
    selected = source_commit or pinned
    commit = subprocess.check_output(['git', 'rev-parse', '--verify', selected+'^{commit}'], cwd=ROOT, text=True).strip()
    checked_blobs = {}
    for component in COMPONENTS.values():
        for code in component['refs']:
            subprocess.run(['git', 'cat-file', '-e', f"{commit}:{code['path']}"], cwd=ROOT, check=True, capture_output=True)
            if code['path'] not in checked_blobs:
                checked_blobs[code['path']] = subprocess.check_output(['git', 'show', f"{commit}:{code['path']}"], cwd=ROOT)
            if sha256(checked_blobs[code['path']]).hexdigest() != code['sha256']:
                raise ValueError(f"Source differs from pinned commit: {code['path']}. Commit the source and pass --source-commit.")
            code['github'] = f"https://github.com/stevekkall-beansgc/savvy-proto/blob/{commit}/{code['path']}#L{code['line']}"
    payload = dict(components=COMPONENTS, sample=sample, lifecycle=json.loads((HERE/'lifecycle-run.json').read_text()), source_commit=commit,
                   repository='stevekkall-beansgc/savvy-proto', branch='codex/medallion-billing',
                   snapshot_date='18 November 2026')
    encoded = json.dumps(payload, separators=(',', ':')).replace('<', chr(92)+'u003c')
    template = (HERE / 'template.html').read_text()
    assets = {'DATA': encoded}
    for key, path in [('FONT', ROOT/'apps/web/public/savvy/fonts/diatype-regular.otf'),
                      ('MEDIUM', ROOT/'apps/web/public/savvy/fonts/diatype-medium.otf'),
                      ('LOGO', ROOT/'apps/web/public/savvy/logo.svg')]:
        assets[key] = base64.b64encode(path.read_bytes()).decode()
    for key, value in assets.items():
        template = template.replace('{{'+key+'}}', value)
    if re.search(r'\{\{[A-Z_]+\}\}', template):
        raise ValueError('Unresolved template token')
    (HERE/'index.html').write_text(template)
    paths=sorted({r['path'] for c in COMPONENTS.values() for r in c['refs']} | {'docs/architecture/sample-run.json','docs/architecture/lifecycle-run.json'})
    (HERE/'source-map.json').write_text(json.dumps({'paths':paths, 'source_commit':commit}, indent=2)+'\n')
    print(f'Built {len(COMPONENTS)} component explanations and {len(paths)} verified code targets.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-commit', help='Repin source links to an existing source commit.')
    build(parser.parse_args().source_commit)
