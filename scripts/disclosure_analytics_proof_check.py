#!/usr/bin/env python3
"""Read-only constructed regression of the actual publication projection SQL."""
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent.parent
context={'service_start':'2027-02-01','service_end_exclusive':'2027-03-01'}
result={'input_manifest_hash':'input','policy_manifest_hash':'policy','context':context,'status':'completed'}
rows=[]
def row(number, kind, external_id, payload, digest):
    rows.append({'evidence_key':f'fixture:{number}','id':number,'tenant_id':'test','entity_id':'test','case_id':'advisor','scenario_id':'fixture', 'kind':kind,'external_id':external_id,'status':'published' if kind=='publication' else 'completed','payload_hash':digest,'payload':payload,'recorded_at':f'2027-02-01T00:00:0{number}Z'})
row(1,'run','run-a',{'result':result},'hash-a')
row(2,'publication','publication-one',{'projection_type':'audience/v1','source_run_id':'run-a','source_run_hash':'hash-a'},'pub-one')
row(3,'publication','publication-two',{'publication_type':'result','run_id':'run-a','run_hash':'hash-a'},'pub-two')
row(4,'run','run-b',{'result':result},'hash-b')
row(5,'run','comparison',{'result':dict(result,context=dict(context,hypothetical=True)),'comparison_only':True},'hash-c')
# Change nothing in source tables: fixture_evidence is a VALUES-derived CTE.
definition='evidence_key text,id bigint,tenant_id text,entity_id text,case_id text,scenario_id text,kind text,external_id text,status text,payload_hash text,payload jsonb,recorded_at timestamptz'
model=(ROOT/'analytics/models/marts/fct_medallion_publication.sql').read_text().replace("{{ ref('stg_medallion_evidence') }}",'fixture_evidence')
encoded=json.dumps(rows).replace("'","''")
query=f"WITH fixture_evidence AS (SELECT * FROM jsonb_to_recordset('{encoded}'::jsonb) AS r({definition})) SELECT json_agg(proof) FROM ({model}) proof"
base=['docker','compose','-f','compose.medallion.yaml','-p','savvy-medallion','exec','-T','db','psql','-XqAt','-v','ON_ERROR_STOP=1','-U','savvy_demo','-d','advisor_economics_synthetic']
response=subprocess.run(base,input=query,text=True,capture_output=True,check=True,cwd=ROOT)
actual={r['selected_run_id']:r for r in json.loads(response.stdout)}
assert set(actual)=={'run-a','run-b','comparison'},actual
assert actual['run-a']['selected_for_current_publication'] is True
assert len(actual['run-a']['publication_proofs'])==2
assert {p['evidence_ref'] for p in actual['run-a']['publication_proofs']}=={'fixture:2','fixture:3'}
assert actual['run-b']['selected_for_current_publication'] is None
assert actual['run-b']['comparison_only'] is None
assert actual['comparison']['selected_for_current_publication'] is False
assert actual['comparison']['billing_evidence_status']=='comparison_not_billed'
assert actual['run-a']['retained_at']!=actual['run-a']['actual_published_at']
assert all(r['snapshot_clock_basis']=='retained_run_clock' for r in actual.values())
report={'status':'passed','writes':0,'checks':10,'scenario':'published run survives later unpublished same-context retry; both publication streams preserved; unknown legacy classification and separate clocks'}
(ROOT/'artifacts/disclosure/analytics-proof.json').write_text(json.dumps(report,indent=2)+'\n')
print('10 constructed publication-proof checks passed; no database writes.')
