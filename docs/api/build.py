#!/usr/bin/env python3
"""Generate public HTTP/GraphQL reference from the checked-in SDL and source."""
import base64
from hashlib import sha256
from html import escape
import json
from pathlib import Path
import re
import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SDL = (ROOT / 'contracts/schema.graphql').read_text()
REPO = 'https://github.com/stevekkall-beansgc/savvy-proto'
SOURCE_COMMIT = json.loads((ROOT / 'docs/architecture/source-map.json').read_text())['source_commit']


def ref(name): return {'$ref': '#/components/schemas/' + name}
def obj(properties, required=(), **extra):
    return {'type': 'object', 'properties': properties, **({'required': list(required)} if required else {}), **extra}
def text(description='', **extra): return {'type': 'string', **({'description': description} if description else {}), **extra}
def enum(name): return re.search(r'enum '+name+r' \{(.*?)\n\}', SDL, re.S).group(1).split()
def code_link(path): return REPO + '/blob/' + SOURCE_COMMIT + '/' + path

DESCRIPTIONS = {
 'billingWorkspace': ('Shared billing', 'Scoped client or internal billing view across both products. Reads issued native documents, exact calculation basis, source executions, policy schedules and correction reviews without running prices or jobs.'),
 'billingCommand': ('Shared billing', 'Shared source intake, policy lifecycle, evaluation, native invoice issue and reviewed correction commands for advisor and RIA cases. Campfire and CLM are mocked.'),
 'disclosureWorkspace': ('Household billing', 'Selected household invoice, account allocations, valuation, terms, credit/refund, compensation and cost evidence. Internal audiences also receive policy and recognition records. The RIA case reports a separately observed cost; it does not infer a platform fee.'),
 'audienceSummary': ('Client experience', 'Published business overview and dated terms for the scoped advisor or RIA.'),
 'audienceStatement': ('Client experience', 'Published statement lines, governing terms, calculation basis and pending items. This baseline book is a separate example from the February household.'),
 'audienceClients': ('Client experience', 'Search and page through underlying clients/accounts before drilling into one account.'),
 'audienceClient': ('Client experience', 'Account detail and its paged observations. Obtain clientId from audienceClients.'),
 'lineageRecords': ('Internal evidence', 'Search retained evidence records. Internal identities only; reads do not run the pipeline.'),
 'lineageRecord': ('Internal evidence', 'Open a retained record and its service/input/output edges. Obtain recordId from lineageRecords or an internal workspace.'),
 'financeWorkspace': ('Internal Finance', 'Cash associations, supplied recognition evidence and unresolved outcomes. The cash/recognition fixture is separate from household billing. Campfire remains mocked.'),
 'medallionWorkspace': ('Internal Product', 'Policy versions, assignments, runs, events and statements for the selected synthetic case and namespace. Client identities are restricted to their own case/workspace.'),
 'productWorkspace': ('Earlier workspaces', 'Earlier broker/internal presentation, terms proposals and comparisons. Advisor access is scoped; RIA identity is excluded from this legacy endpoint.'),
 'entitlementLedger': ('Earlier workspaces', 'Earlier entitlement ledger projection. RIA identity is excluded.'),
 'brokerBook': ('Earlier workspaces', 'Earlier broker book with exact earned, coverage and incremental cash amounts. RIA identity is excluded.'),
 'collections': ('Earlier workspaces', 'Earlier source-observation collection projection. RIA identity is excluded. This is not a live collections integration.'),
 'reconciliation': ('Earlier workspaces', 'Earlier retained reconciliation state for a period. RIA identity is excluded. No live Campfire posting is established.'),
 'reviewPacket': ('Earlier workspaces', 'Earlier review evidence for a retained run. RIA identity is excluded.'),
 'run': ('Earlier workspaces', 'Earlier retained run by ID. RIA identity is excluded.'),
 'workbench': ('Earlier workspaces', 'Earlier scoped workbench state. RIA identity is excluded.'),
 'disclosureCommand': ('Household policies', 'Save draft → compare → independent Legal/Finance reviews → publish → assign → evaluate. Original invoices remain retained; a changed billed result requires correction.'),
 'medallionCommand': ('Billing events and policies', 'Baseline policy lifecycle, source deliveries, one-time events, confirmed payment evidence, applications, reversals and period controls. Actions have independent role and source/evidence checks.'),
 'financeCommand': ('Internal Finance', 'Record or reverse a local cash association, or retain a mocked accounting acknowledgment. These commands do not execute cash or post a live journal.'),
 'workbenchCommand': ('Earlier workspaces', 'Earlier operational commands and commercial proposals. Existing command-specific reviews and scopes apply; RIA identity is excluded.'),
}
DEFAULTS = {'caseId': 'advisor', 'audience': 'client', 'workspace': 'advisor', 'scenarioId': 'baseline', 'limit': 20, 'offset': 0, 'pageChanges': True,
 'search': None, 'clientId': 'REPLACE_WITH_CLIENT_ID', 'recordId': 'REPLACE_WITH_RECORD_ID', 'brokerId': 'broker-alex',
 'runId': 'REPLACE_WITH_RUN_ID', 'id': 'REPLACE_WITH_RUN_ID', 'knowledgeCutoff': '2026-10-02T23:00:00Z',
 'periodStart': '2026-09-01', 'periodEndExclusive': '2026-10-01', 'businessDate': '2026-11-13'}


def catalog():
    output=[]
    for kind in ['Query','Mutation']:
        body=re.search(r'type '+kind+r' \{(.*?)\n\}', SDL,re.S).group(1)
        for line in body.splitlines():
            if not line.strip(): continue
            match=re.fullmatch(r'\s*(\w+)(?:\((.*?)\))?: ([\w!\[\]]+)\s*',line)
            if not match: raise ValueError('Unsupported SDL field: '+line)
            name,args,returns=match.groups()
            arguments=[{'name':a,'type':t,'required':t.endswith('!')} for a,t in re.findall(r'(\w+): ([\w!\[\]]+)',args or '')]
            declarations=', '.join('$'+a['name']+': '+a['type'] for a in arguments)
            bindings=', '.join(a['name']+': $'+a['name'] for a in arguments)
            selection=' { data errors { code message path } }' if kind=='Mutation' else ' { id name completeness earned { minorUnits currency } coverage { minorUnits currency } incrementalCash { minorUnits currency } customers }' if returns.rstrip('!')=='BrokerBook' else ' { id status policyHash inputManifestHash businessDate knowledgeCutoff data }' if returns.rstrip('!')=='Run' else ''
            query=('query' if kind=='Query' else 'mutation')+' '+name[0].upper()+name[1:]+('('+declarations+')' if arguments else '')+' { '+name+('('+bindings+')' if arguments else '')+selection+' }'
            variables={a['name']:DEFAULTS.get(a['name']) for a in arguments if a['name'] in DEFAULTS}
            if name=='financeWorkspace':variables['caseId']='ria'
            if kind=='Mutation':variables={'action': {'billingCommand':'SAVE_POLICY','disclosureCommand':'SAVE_POLICY','medallionCommand':'SUBMIT_EVENT','financeCommand':'FINANCE_ASSOCIATE','workbenchCommand':'SAVE_TERMS_PROPOSAL'}[name], 'input':{},'idempotencyKey':'REPLACE_WITH_UNIQUE_KEY'}
            if name=='billingCommand':variables['caseId']='advisor'
            if name=='billingWorkspace':variables.pop('recordId',None)
            group,description=DESCRIPTIONS[name]
            output.append({'name':name,'kind':kind.lower(),'group':group,'description':description,'arguments':arguments,'returns':returns,'request':{'query':query, 'variables':variables},'example_note':'Replace identifiers with IDs returned by reads. Mutation input shown separately below; the empty catalog input is a shape template.' if kind=='Mutation' else 'Replace identifiers prefixed REPLACE_WITH using IDs from a preceding read.'})
    return output


operations=catalog()
minor=text('Exact minor units as a decimal integer string; unknown amounts are null, not zero.',pattern=r'^-?[0-9]+$')
positive={**minor,'pattern':r'^[1-9][0-9]*$'}
date=text('API end dates are exclusive; UI last-day dates are inclusive.',format='date')
key=text('Scoped by actor, command and tenant/entity. Reuse only for the identical input.',pattern=r'^[a-zA-Z0-9_-]{1,100}$')
case={'type':'string','enum':['advisor','ria']}
policy=obj({'basis':{'enum':['ending_value','average_daily_balance','net_worth','fixed','hourly','optional_service']},'cadence':{'enum':['monthly','quarterly']},'annual_rate':{'type':['string','null'],'maxLength':40,'pattern':r'^\d+(?:/[1-9]\d*)?$','description':'Exact nonnegative rational fraction, e.g. 3/250 = 1.2% annually. Accepted combinations are validated by DisclosurePolicy.'},'minimum_minor':{'anyOf':[minor,{'type':'null'}]},'fixed_amount_minor':{'anyOf':[minor,{'type':'null'}]},'hourly_rate_minor':{'anyOf':[minor,{'type':'null'}]},'optional_amount_minor':{'anyOf':[minor,{'type':'null'}]},'optional_service':{'enum':['none','accepted']},'service_mode':{'enum':['full','partial',None]}},['basis','cadence','optional_service'],additionalProperties=False,description='Named household policy treatments. Monthly ending value supports a group minimum; other bases require their matching source evidence. Unsupported field combinations fail validation. The policy graph is data; Economics::Engine performs all arithmetic.')
schemas={
 'GraphQLRequest':obj({'query':text('GraphQL document, maximum 50,000 UTF-8 bytes at Rails.'),'variables':{'type':['object','null'],'additionalProperties':True},'operationName':{'type':['string','null']}},['query']),
 'GraphQLError':obj({'message':text(),'path':{'type':'array','items':{'type':['string','integer']}},'extensions':obj({'code':text()},additionalProperties=True),'locations':{'type':'array','items':obj({'line':{'type':'integer'},'column':{'type':'integer'}})}},['message'],additionalProperties=True),
 'GraphQLResponse':obj({'data':{'type':['object','null'],'additionalProperties':True},'errors':{'type':'array','items':ref('GraphQLError')},'extensions':{'type':'object','additionalProperties':True}},additionalProperties=True,description='HTTP 200 may contain top-level GraphQL errors. Command domain errors are nested in data.<command>.errors; inspect both before accepting a write.'),
 'HttpError':obj({'error':text(),'errors':{'type':'array','items':ref('GraphQLError')}},additionalProperties=True),
 'DomainError':obj({'code':text(),'message':text(),'path':{'type':'array','items':text()}},['code','message','path']),
 'CommandResult':obj({'data':{},'errors':{'type':'array','items':ref('DomainError')},'run':{}},['errors'],description='Command-specific data is a GraphQL JSON scalar. Run is optionally selected on Payload. Empty errors alone does not establish cash execution or accounting recognition.'),
 'MinorUnits':minor,'IdempotencyKey':key,'HouseholdPolicy':policy,
 'SavePolicyInput':obj({'case_id':{'const':'advisor'},'base_policy_id':text(),'policy':ref('HouseholdPolicy'),'effective_from':date,'effective_to':{'anyOf':[date,{'type':'null'}]},'reason':text()},['case_id','base_policy_id','policy','effective_from','effective_to','reason'],additionalProperties=False),
 'ComparePolicyInput':obj({'case_id':{'const':'advisor'},'policy_id':text(),'baseline_run_id':text()},['case_id','policy_id','baseline_run_id'],additionalProperties=False),
 'ReviewPolicyInput':obj({'case_id':{'const':'advisor'},'comparison_id':text(),'decision':{'enum':['approve','reject']},'reason':text()},['case_id','comparison_id','decision','reason'],additionalProperties=False),
 'PublishPolicyInput':obj({'case_id':{'const':'advisor'},'policy_id':text(),'comparison_id':text()},['case_id','policy_id','comparison_id'],additionalProperties=False),
 'AssignPolicyInput':obj({'case_id':{'const':'advisor'},'policy_id':text(),'subject_id':{'const':'disclosure-alder-household'},'effective_from':date,'effective_to':date,'reason':text(),'supersedes_assignment_id':text()},['case_id','policy_id','subject_id','effective_from','effective_to','reason'],additionalProperties=False),
 'EvaluateInput':obj({'case_id':{'const':'advisor'},'knowledge_cutoff':text(format='date-time')},['case_id','knowledge_cutoff'],additionalProperties=False),
 'OneTimeEvent':obj({'id':text(),'revision':{'type':'integer','minimum':1},'kind':{'enum':['one_time_charge','one_time_credit','compensation_entitlement','payout_request']},'amount_minor':positive,'currency':{'const':'USD'},'debtor_id':text(),'creditor_id':text(),'subject_id':text(),'reason':text(),'economic_date':date,'posting_period':text(pattern=r'^\d{4}-\d{2}$'),'policy_id':text(),'event_policy_id':text(),'original_id':text(),'original_revision':{'type':'integer','minimum':1},'original_hash':text(),'reason_code':text()},['id','revision','kind','amount_minor','currency','debtor_id','creditor_id','subject_id','reason','economic_date','posting_period','policy_id'],additionalProperties=False,description='Baseline September 2026 event input. Advisor supports compensation_entitlement and payout_request, firm-demo → advisor-demo. RIA supports one_time_charge (ria-harbor → firm-demo) and one_time_credit (reverse direction). Amount is positive; kind and parties carry direction. Non-payout items need a published event_policy_id. Revisions must bind original identity/revision/hash.'),
 'SubmitEventInput':obj({'case_id':case,'scenario_id':text(default='baseline'),'event':ref('OneTimeEvent')},['case_id','event']),
 'ReviewEventInput':obj({'case_id':case,'scenario_id':text(default='baseline'),'event_id':text(),'revision':{'type':'integer','minimum':1},'expected_hash':text(),'decision':{'enum':['approved','rejected']}},['case_id','event_id','revision','expected_hash','decision']),
 'CashAssociationInput':obj({'payment_id':text(),'invoice_id':text(),'currency':{'const':'USD'},'amount_minor':positive,'posting_period':text(pattern=r'^\d{4}-\d{2}$'),'reason':text()},['payment_id','invoice_id','currency','amount_minor','posting_period','reason'],additionalProperties=False),
 'CashReversalInput':obj({'application_id':text(),'reason':text(),'posting_period':text(pattern=r'^\d{4}-\d{2}$')},['application_id','reason','posting_period'],additionalProperties=False),
}

def command_example(family,action,input_value):
    op=next(o for o in operations if o['name']==family)
    return {'query':op['request']['query'],'variables':{'action':action,'input':input_value,'idempotencyKey':'docs-'+action.lower().replace('_','-')+'-001',**({'caseId':'advisor'} if family=='billingCommand' else {})}}

policy_value={'basis':'ending_value','cadence':'monthly','annual_rate':'33/2500','minimum_minor':None,'fixed_amount_minor':None,'optional_service':'none'}
inputs={
 'SAVE_POLICY':('SavePolicyInput','operator',{'case_id':'advisor','base_policy_id':'disclosure-policy-v1','policy':policy_value,'effective_from':'2027-02-01','effective_to':'2027-03-01','reason':'Compare a proposed annual rate'}),
 'COMPARE_POLICY':('ComparePolicyInput','operator',{'case_id':'advisor','policy_id':'REPLACE_WITH_DRAFT_POLICY_ID','baseline_run_id':'disclosure-run-v1'}),
 'REVIEW_POLICY':('ReviewPolicyInput','legal or finance',{'case_id':'advisor','comparison_id':'REPLACE_WITH_COMPARISON_ID','decision':'approve','reason':'Reviewed exact comparison and evidence'}),
 'PUBLISH_POLICY':('PublishPolicyInput','operator',{'case_id':'advisor','policy_id':'REPLACE_WITH_DRAFT_POLICY_ID','comparison_id':'REPLACE_WITH_COMPARISON_ID'}),
 'ASSIGN_POLICY':('AssignPolicyInput','operator',{'case_id':'advisor','policy_id':'REPLACE_WITH_PUBLISHED_POLICY_ID','subject_id':'disclosure-alder-household','effective_from':'2027-02-01','effective_to':'2027-03-01','supersedes_assignment_id':'disclosure-assignment-v1','reason':'Assign the reviewed policy for this interval'}),
 'EVALUATE':('EvaluateInput','operator',{'case_id':'advisor','knowledge_cutoff':'2027-02-28T23:59:59Z'}),
}
command_details=[{'family':'disclosureCommand','action':action,'schema':schema,'role':role,'request':command_example('disclosureCommand',action,value)} for action,(schema,role,value) in inputs.items()]
command_details += [
 {'family':'medallionCommand','action':'SUBMIT_EVENT','schema':'SubmitEventInput','role':'operator or finance','request':command_example('medallionCommand','SUBMIT_EVENT',{'case_id':'advisor','scenario_id':'baseline','event':{'id':'docs-payout-request-001','revision':1,'kind':'payout_request','amount_minor':'25000','currency':'USD','debtor_id':'firm-demo','creditor_id':'advisor-demo','subject_id':'advisor-demo','reason':'Request a one-time advisor payout','economic_date':'2026-09-15','posting_period':'2026-09','policy_id':'advisor-policy-v1'}})},
 {'family':'medallionCommand','action':'REVIEW_EVENT','schema':'ReviewEventInput','role':'finance','request':command_example('medallionCommand','REVIEW_EVENT',{'case_id':'advisor','event_id':'REPLACE_WITH_EVENT_ID','revision':1,'expected_hash':'REPLACE_WITH_EVENT_HASH','decision':'approved'})},
 {'family':'financeCommand','action':'FINANCE_ASSOCIATE','schema':'CashAssociationInput','role':'finance','request':command_example('financeCommand','FINANCE_ASSOCIATE',{'payment_id':'REPLACE_WITH_PAYMENT_ID','invoice_id':'REPLACE_WITH_INVOICE_ID','currency':'USD','amount_minor':'30000','posting_period':'2027-01','reason':'Associate confirmed cash with the suggested invoice'})},
 {'family':'financeCommand','action':'FINANCE_REVERSE','schema':'CashReversalInput','role':'finance','request':command_example('financeCommand','FINANCE_REVERSE',{'application_id':'REPLACE_WITH_APPLICATION_ID','posting_period':'2027-01','reason':'Reverse the local cash association'})},
]
commands={'disclosureCommand':['BOOTSTRAP',*inputs.keys()], 'medallionCommand':enum('MedallionCommand'),'financeCommand':enum('FinanceCommand'),'workbenchCommand':enum('Command')}
# The shared command contract mirrors BillingPlatform::INPUTS; examples bind returned IDs.
shared_policy={'version':'service-v2','allocation':'equal','invoice_timing':'arrears','components':[{'id':'asset_fee','kind':'aum','basis':'daily','rate':'3/250','day_basis':365},{'id':'service','kind':'flat','amount_minor':5000,'proration':'service_days'},{'id':'one_time','kind':'events','direction':'charge'}],'compensation':{'share':'4/5'}}
mapping={'format':'json','records_path':'records','fields':{'id':'id','revision':'revision','type':'type','observed_at':'observed_at','billing_subject_id':'billing_subject_id','customer_id':'customer_id','account_id':'account_id','date':'date','amount_minor':'amount_minor','currency':'currency'}}
shared={
 'REGISTER_SOURCE':('operator',{'name':'custodian-feed','mapping':mapping}),
 'INGEST':('operator',{'source_id':'REPLACE_WITH_SOURCE_ID','delivery_key':'docs-delivery-001','raw':'{"records":[]}'}),
 'REPLAY':('operator',{'delivery_id':'REPLACE_WITH_DELIVERY_ID','source_id':'REPLACE_WITH_CURRENT_MAPPING_ID'}),
 'SAVE_POLICY':('operator',{'policy':shared_policy,'effective_from':'2026-10-01','effective_to':None,'reason':'Propose a composed service policy'}),
 'COMPARE_POLICY':('operator',{'policy_id':'REPLACE_WITH_POLICY_ID','subject_id':'REPLACE_WITH_SUBJECT_ID','service_start':'2026-10-01','service_end_exclusive':'2026-11-01'}),
 'REVIEW_POLICY':('legal or finance',{'comparison_id':'REPLACE_WITH_COMPARISON_ID','decision':'approved','reason':'Review the exact comparison','document_ref':{'system':'mock_clm','document_id':'terms-001','version':'v1'}}),
 'PUBLISH_POLICY':('operator',{'comparison_id':'REPLACE_WITH_COMPARISON_ID'}),
 'ASSIGN_POLICY':('operator',{'policy_id':'REPLACE_WITH_POLICY_ID','subject_id':'REPLACE_WITH_SUBJECT_ID','effective_from':'2026-10-01','effective_to':'2026-11-01','reason':'Assign reviewed terms','expected_schedule_hash':'REPLACE_WITH_SCHEDULE_HASH'}),
 'EVALUATE':('operator',{'subject_id':'REPLACE_WITH_SUBJECT_ID','service_start':'2026-10-01','service_end_exclusive':'2026-11-01'}),
 'ISSUE_INVOICE':('operator',{'run_id':'REPLACE_WITH_RUN_ID','posting_period':'2026-11','due_on':'2026-12-18'}),
 'PROPOSE_CORRECTION':('operator',{'document_id':'REPLACE_WITH_ORIGINAL_INVOICE_ID','run_id':'REPLACE_WITH_NEW_RUN_ID','posting_period':'2026-11','reason':'Correct newly received evidence'}),
 'REVIEW_CORRECTION':('finance',{'proposal_id':'REPLACE_WITH_PROPOSAL_ID','decision':'approved','reason':'Approve the exact per-account differences'}),
 'ISSUE_CORRECTION':('operator',{'proposal_id':'REPLACE_WITH_PROPOSAL_ID'}),
 'REVIEW_EVENT':('finance',{'record_id':'REPLACE_WITH_RECORD_ID','expected_hash':'REPLACE_WITH_HASH','decision':'approved','reason':'Review a one-time event'}),
 'CLOSE_PERIOD':('finance',{'posting_period':'2026-11','reason':'Close the posting month'}),
}
shared_fields={'REGISTER_SOURCE':['name','mapping'],'INGEST':['source_id','delivery_key','raw','raw_base64'],'REPLAY':['delivery_id','source_id'],'SAVE_POLICY':['policy','effective_from','effective_to','reason'],'COMPARE_POLICY':['policy_id','baseline_policy_id','subject_id','service_start','service_end_exclusive'],'REVIEW_POLICY':['comparison_id','decision','reason','document_ref'],'PUBLISH_POLICY':['comparison_id'],'ASSIGN_POLICY':['policy_id','subject_id','effective_from','effective_to','reason','expected_schedule_hash'],'EVALUATE':['subject_id','service_start','service_end_exclusive'],'ISSUE_INVOICE':['run_id','posting_period','due_on'],'PROPOSE_CORRECTION':['document_id','run_id','posting_period','reason'],'REVIEW_CORRECTION':['proposal_id','decision','reason'],'ISSUE_CORRECTION':['proposal_id'],'REVIEW_EVENT':['record_id','expected_hash','decision','reason'],'CLOSE_PERIOD':['posting_period','reason']}
schemas['SharedPolicy']=obj({'version':text(),'allocation':{'enum':['equal','balance']},'purpose':{'enum':['billing','earnings']},'invoice_timing':{'enum':['advance','arrears']},'components':{'type':'array','minItems':1,'items':obj({'id':text(),'kind':{'enum':['aum','flat','per_account','hourly','events','observation','earned_share']}},['id','kind'],additionalProperties=True)},'graph':{'type':'object','description':'Validated typed primitive graph; mandatory assessed USD charge obligation and source requirements.'},'input_requirements':{'type':'object'},'minimum_minor':minor,'cap_minor':minor,'compensation':{'type':'object'}},['version'],additionalProperties=False,description='Use components OR graph. Kind-specific field validation is enforced by BillingPolicy. AUM supports annual rate, dated standard/promotion/targeted rates or progressive tiers. Observation outputs stay separate from invoices. Only approved typed operators execute; no source code is accepted.')
schemas['SourceMapping']=obj({'format':{'enum':['json','ndjson']},'records_path':text(),'fields':{'type':'object','additionalProperties':text()},'constants':{'type':'object'},'coercions':{'type':'object','additionalProperties':{'enum':['integer','decimal_usd','rational_decimal','boolean','us_date','epoch_seconds','identifier','string']}}},['format','fields'],additionalProperties=False,description='Versioned canonical field mappings. Original bytes are retained before parsing; binary or invalid input is quarantined. Registering a new version requires replay before normalized records become current.')
shared.update({
 'APPLY_CASH':('finance',{'target_id':'REPLACE_WITH_ROOT_ID','record_id':'REPLACE_WITH_SOURCE_RECORD_ID','expected_hash':'REPLACE_WITH_SOURCE_HASH','expected_ledger_hash':'REPLACE_WITH_LEDGER_HASH','amount_minor':'10000','posting_period':'2026-11','reason':'Associate independently confirmed cash'}),
 'REVERSE_CASH':('finance',{'application_id':'REPLACE_WITH_APPLICATION_ID','expected_hash':'REPLACE_WITH_APPLICATION_HASH','posting_period':'2026-11','reason':'Reverse an operational association'}),
 'REQUEST_REFUND':('finance',{'target_id':'REPLACE_WITH_ROOT_ID','expected_ledger_hash':'REPLACE_WITH_LEDGER_HASH','amount_minor':'10000','posting_period':'2026-11','reason':'Request an available customer credit'}),
 'CANCEL_REFUND':('finance',{'request_id':'REPLACE_WITH_REQUEST_ID','expected_hash':'REPLACE_WITH_REQUEST_HASH','posting_period':'2026-11','reason':'Cancel the unapplied remainder'}),
 'PACKAGE_ACCOUNTING':('finance',{'target_id':'REPLACE_WITH_ROOT_ID','expected_ledger_hash':'REPLACE_WITH_LEDGER_HASH','treatment_ref':{'system':'mock_campfire','id':'fictional-finance-treatment','version':'v1'},'posting_period':'2026-11','reason':'Prepare a versioned mock accounting package'}),
 'ACCEPT_ACCOUNTING':('finance',{'record_id':'REPLACE_WITH_SOURCE_RECORD_ID','expected_hash':'REPLACE_WITH_SOURCE_HASH'}),
 'PROPOSE_PAYABLE':('operator',{'run_id':'REPLACE_WITH_EARNINGS_RUN_ID','posting_period':'2026-11','reason':'Prepare native earnings payable'}),
 'REVIEW_PAYABLE':('finance',{'proposal_id':'REPLACE_WITH_PROPOSAL_ID','decision':'approved','reason':'Review exact earnings calculation'}),
 'ISSUE_PAYABLE':('operator',{'proposal_id':'REPLACE_WITH_PROPOSAL_ID'}),
 'QUEUE_BATCH':('operator',{'subjects':['REPLACE_WITH_SUBJECT_ID'],'service_start':'2026-10-01','service_end_exclusive':'2026-11-01','reason':'Queue retained period evaluation'}),
 'RETRY_WORK':('operator',{'job_id':'REPLACE_WITH_JOB_ID','reason':'Retry retained failed or quarantined work'}),
})
shared_fields.update({action:list(value) for action,(_,value) in shared.items() if action not in shared_fields})
shared_fields['INGEST']+=['defer','run_at'];shared_fields['EVALUATE']+=['purpose'];shared_fields['QUEUE_BATCH']+=['run_at','purpose'];shared_fields['APPLY_CASH']+=['request_id'];shared_fields['RETRY_WORK']+=['source_id']
for action,(role,value) in shared.items():
    props={k:text() for k in shared_fields[action]}
    for field in ['effective_from','effective_to','service_start','service_end_exclusive','due_on']:
        if field in props:props[field]=date
    if action=='SAVE_POLICY':props.update(policy=ref('SharedPolicy'),effective_to={'anyOf':[date,{'type':'null'}]})
    if action=='REGISTER_SOURCE':props['mapping']=ref('SourceMapping')
    if 'purpose' in props:props['purpose']={'enum':['billing','earnings']}
    if 'amount_minor' in props:props['amount_minor']=positive
    if 'defer' in props:props['defer']={'type':'boolean'}
    if 'run_at' in props:props['run_at']=text(format='date-time')
    if 'subjects' in props:props['subjects']={'type':'array','minItems':1,'maxItems':1000,'uniqueItems':True,'items':text()}
    if 'treatment_ref' in props:props['treatment_ref']=obj({'system':{'const':'mock_campfire'},'id':text(),'version':text()},['system','id','version'],additionalProperties=False)
    if 'decision' in props:props['decision']={'enum':['approved','rejected']}
    if 'document_ref' in props:props['document_ref']=obj({'system':{'const':'mock_clm'},'document_id':text(),'version':text()},['system','document_id','version'],additionalProperties=False)
    name='Shared'+''.join(x.title() for x in action.lower().split('_'))+'Input'
    schemas[name]=obj(props,list(value),additionalProperties=False)
    command_details.append({'family':'billingCommand','action':action,'schema':name,'role':role,'request':command_example('billingCommand',action,value)})
commands['billingCommand']=list(shared)
read_example=next(o['request'] for o in operations if o['name']=='disclosureWorkspace')
read_example['variables']['limit']=100


def response(description,schema):return {'description':description,'content':{'application/json':{'schema':ref(schema)}}}
post={'summary':'Execute GraphQL queries or commands','operationId':'executeGraphQL','tags':['GraphQL transport'],
 'description':'GraphQL POST envelope. Query and Mutation fields are enumerated in x-graphql-operations and in the downloadable authoritative SDL. No REST resources, MCP endpoint or WebMCP registration are implemented by this document. All fixtures are synthetic; integrations remain mocked. This reference does not send live requests.',
 'parameters':[{'name':'X-Demo-Role','in':'header','required':False,'description':'Simulated local identity only, not an authentication credential. Omission currently defaults to operator. Real identity/account authorization is required before a production or agent integration.','schema':{'type':'string','enum':['advisor','ria','operator','finance','legal','auditor'],'default':'operator'}}],
 'requestBody':{'required':True,'content':{'application/json':{'schema':ref('GraphQLRequest'),'examples':{'householdRead':{'summary':'Read February household billing','value':read_example},'saveDraftPolicy':{'summary':'Save a draft; does not activate or bill','value':command_details[0]['request']},'submitPayoutRequest':{'summary':'Draft September payout request; does not execute payment','value':command_details[6]['request']}}}}},
 'responses':{'200':response('GraphQL result, possibly containing top-level or nested domain errors.','GraphQLResponse'),'400':response('Malformed JSON or invalid GraphQL envelope forwarded by Rails.','HttpError'),'403':response('Origin or simulated identity rejected.','HttpError'),'500':response('Rails service error or invalid local API proxy configuration.','HttpError'),'413':response('Request body exceeds the transport limit.','HttpError'),'503':response('Next proxy cannot reach its loopback Rails API or the request times out.','HttpError')},
 'security':[{'CloudflareAccessSession':[]}],
 'x-hosted-access':'The existing Cloudflare Access gate can redirect an unauthenticated request to login or reject it before the application handles the request.',
 'x-limits':{'proxy_body_character_limit':1048576,'rails_body_utf8_byte_limit':1048576,'graphql_document_utf8_byte_limit':50000,'graphql_max_depth':10,'graphql_max_complexity':150}}
local_post=json.loads(json.dumps(post));local_post['operationId']='executeLocalGraphQL';local_post['summary']='Execute GraphQL directly on the loopback Rails API';local_post['security']=[];local_post['responses'].pop('503');local_post['responses'].update({s:response(desc,'HttpError') for s,desc in {'400':'Malformed JSON or invalid GraphQL envelope.','415':'Content-Type must be application/json.','500':'Unhandled local service error.'}.items()})
spec={'openapi':'3.1.1','info':{'title':'Savvy billing prototype API','version':'0.8.0','description':'Current synthetic Rails/GraphQL implementation. Savvy owns billing obligations, invoices/lines and custodial instructions. One Economics::Engine evaluates policy data. Campfire and CLM remain mocked. The public API reference is static documentation; hosted operations require the existing Cloudflare Access login. Simulated X-Demo-Role identities are not production authentication.'},
 'servers':[{'url':'https://savvy-proto.beanshop.top','description':'Device-hosted full application; Cloudflare Access browser login required.'}],
 'externalDocs':{'description':'Authoritative GraphQL SDL in the repository','url':code_link('contracts/schema.graphql')},
 'tags':[{'name':'GraphQL transport'},{'name':'Local service'}],
 'paths':{'/api/graphql':{'post':post},'/graphql':{'servers':[{'url':'http://127.0.0.1:3108','description':'API slot A Rails API; loopback only.'},{'url':'http://127.0.0.1:3109','description':'API slot B Rails API slot; loopback only.'}],'post':local_post},'/health':{'servers':[{'url':'http://127.0.0.1:3108','description':'API slot A Rails health; loopback only.'},{'url':'http://127.0.0.1:3109','description':'API slot B Rails health slot; loopback only.'}],'get':{'operationId':'localHealth','summary':'Inspect local synthetic service health','tags':['Local service'],'security':[],'responses':{'200':{'description':'Current local service metadata.','content':{'application/json':{'schema':obj({'status':{'const':'ok'},'synthetic':{'const':True},'connected':{'const':False},'contract_version':text(),'engine_version':text(),'source_revision':text(),'immutable_preview':{'type':'boolean'},'eager_load':{'type':'boolean'},'reloading_enabled':{'type':'boolean'}},['status','synthetic','connected','contract_version','engine_version'])}}}}}}},
 'components':{'securitySchemes':{'CloudflareAccessSession':{'type':'apiKey','in':'cookie','name':'CF_Authorization','description':'Existing Cloudflare Access browser session. This documents the hosted gate; it is not OAuth for an MCP client. Do not put a session cookie in documentation or source.'}},'schemas':schemas},
 'x-graphql-operations':operations,'x-command-families':commands,'x-command-examples':command_details,
 'x-contract-sources':{'graphql_sdl':'contracts/schema.graphql','graphql_sdl_sha256':sha256(SDL.encode()).hexdigest(),'source_commit':SOURCE_COMMIT,'controller':'apps/api/app/controllers/graphql_controller.rb','proxy':'apps/web/app/api/graphql/route.ts'},
 'x-agent-interfaces':{'mcp':{'implemented':False},'webmcp':{'implemented':False},'note':'The API can underpin future named tools. Production identity, protocol adapters and client compatibility still need implementation.'}}
(HERE/'openapi.yaml').write_text(yaml.safe_dump(spec,sort_keys=False,allow_unicode=True,width=110))

# The reference is self-contained: no remote JavaScript, live requests or credential fields.
cards=[]
for operation in operations:
    argument_rows=''.join('<tr><td><code>'+escape(a['name'])+'</code></td><td><code>'+escape(a['type'])+'</code></td><td>'+('Required' if a['required'] else 'Optional')+'</td></tr>' for a in operation['arguments'])
    body='<p>'+escape(operation['description'])+'</p><p class="meta">Returns <code>'+escape(operation['returns'])+'</code></p>'
    if argument_rows:body+='<div class="scroll"><table><thead><tr><th>Argument</th><th>Type</th><th>Presence</th></tr></thead><tbody>'+argument_rows+'</tbody></table></div>'
    body+='<p class="meta">'+escape(operation['example_note'])+'</p><pre>'+escape(json.dumps(operation['request'],indent=2))+'</pre>'
    if operation['name'] in commands:body+='<h3>Supported actions</h3><div class="action-list">'+''.join('<code>'+escape(action)+'</code>' for action in commands[operation['name']])+'</div>'
    cards.append('<details class="operation" id="'+operation['name']+'" data-group="'+escape(operation['group'])+'"><summary><span class="badge '+operation['kind']+'">'+operation['kind'].upper()+'</span><strong>'+operation['name']+'</strong><span class="group">'+operation['group']+'</span></summary><div class="operation-body">'+body+'</div></details>')
examples=[]
for entry in command_details:
    examples.append('<details class="operation"><summary><span class="badge mutation">COMMAND</span><strong>'+entry['action']+'</strong><span class="group">'+escape(entry['role'])+'</span></summary><div class="operation-body"><p><code>'+entry['family']+'</code> · Input schema: <code>'+entry['schema']+'</code></p><p class="meta">Replace returned IDs and choose a unique idempotencyKey for each intent. Examples are shown only; this page has no request execution controls.</p><pre>'+escape(json.dumps(entry['request'],indent=2))+'</pre><h3>Input schema</h3><pre>'+escape(json.dumps(schemas[entry['schema']],indent=2))+'</pre></div></details>')
page=(HERE/'template.html').read_text()
assets={'OPERATIONS':'\n'.join(cards),'EXAMPLES':'\n'.join(examples),'QUERY_COUNT':str(sum(x['kind']=='query' for x in operations)),'MUTATION_COUNT':str(sum(x['kind']=='mutation' for x in operations)),'SOURCE_COMMIT':SOURCE_COMMIT,'SOURCE_SHORT':SOURCE_COMMIT[:7],'GROUPS':''.join('<option>'+escape(g)+'</option>' for g in dict.fromkeys(o['group'] for o in operations))}
for key,path in [('FONT','fonts/diatype-regular.otf'),('MEDIUM','fonts/diatype-medium.otf'),('LOGO','logo.svg')]:assets[key]=base64.b64encode((ROOT/'apps/web/public/savvy'/path).read_bytes()).decode()
for key,value in assets.items():page=page.replace('{{'+key+'}}',value)
if re.search(r'\{\{[A-Z_]+\}\}',page):raise ValueError('Unresolved reference template token')
(HERE/'index.html').write_text(page)
print(f'Built OpenAPI 3.1.1, {len(operations)} GraphQL operations and {len(command_details)} command examples.')
