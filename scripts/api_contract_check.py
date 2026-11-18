#!/usr/bin/env python3
"""Validate OpenAPI, SDL coverage, examples and source drift; optional read-only live probe."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request
import yaml
from graphql import build_schema, parse, validate, get_variable_values
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec

ROOT=Path(__file__).resolve().parent.parent
API_ORIGINS={'http://127.0.0.1:3102','http://127.0.0.1:3108','http://127.0.0.1:3109'}


def check(live=False):
    sdl=(ROOT/'contracts/schema.graphql').read_text()
    spec=yaml.safe_load((ROOT/'docs/api/openapi.yaml').read_text())
    validate_spec(spec)
    schema=build_schema(sdl)
    fields={**schema.query_type.fields,**schema.mutation_type.fields}
    operations=spec['x-graphql-operations']
    assert {o['name'] for o in operations}==set(fields), 'GraphQL catalog does not cover the SDL'
    assert len(operations)==len(fields), 'Duplicate catalog entry'
    for operation in operations:
        name=operation['name'];field=fields[name]
        assert operation['returns']==str(field.type), name+' return type drift'
        assert [(a['name'],a['type']) for a in operation['arguments']]==[(name,str(arg.type)) for name,arg in field.args.items()],name+' argument drift'
        document=parse(operation['request']['query'])
        assert not validate(schema,document),name+' example query is invalid'
        values=get_variable_values(schema,document.definitions[0].variable_definitions,operation['request']['variables'])
        assert not isinstance(values,list),name+' example variables are invalid'
    for entry in spec['x-command-examples']:
        request=entry['request'];document=parse(request['query'])
        assert not validate(schema,document),entry['action']+' mutation is invalid'
        Draft202012Validator({'$ref':'#/components/schemas/'+entry['schema'],'components':spec['components']}).validate(request['variables']['input'])
        assert request['variables']['action'] in spec['x-command-families'][entry['family']]
    # Presence and date shape are part of the JSON input contract, even though
    # interval containment and fixture-specific bounds are enforced by the API.
    for schema_name in ['SavePolicyInput','AssignPolicyInput']:
        example=next(e['request']['variables']['input'] for e in spec['x-command-examples'] if e['schema']==schema_name)
        validator=Draft202012Validator({'$ref':'#/components/schemas/'+schema_name,'components':spec['components']},format_checker=FormatChecker())
        missing=dict(example); missing.pop('effective_to')
        assert not validator.is_valid(missing),schema_name+' accepts omitted effective_to'
        invalid=dict(example,effective_to='2027-02-30')
        assert not validator.is_valid(invalid),schema_name+' accepts malformed date'
        null_end=dict(example,effective_to=None)
        assert validator.is_valid(null_end)==(schema_name=='SavePolicyInput'),schema_name+' null effective_to drift'
    for field,enum in [('medallionCommand','MedallionCommand'),('financeCommand','FinanceCommand'),('workbenchCommand','Command')]:
        assert set(spec['x-command-families'][field])==set(schema.get_type(enum).values),field+' action drift'
    source=(ROOT/'apps/api/app/graphql/demo_graph.rb').read_text()
    mapping=re.search(r"methods=\{('BOOTSTRAP'=>:bootstrap,.*?)\}",source,re.S).group(1)
    assert set(spec['x-command-families']['disclosureCommand'])==set(re.findall(r"'([A-Z_]+)'=>",mapping))
    controller=(ROOT/'apps/api/app/controllers/graphql_controller.rb').read_text()
    assert 'contract_version: "'+spec['info']['version']+'"' in controller
    assert spec['x-contract-sources']['graphql_sdl_sha256']==sha256(sdl.encode()).hexdigest()
    for name in ['contracts/schema.graphql','apps/api/app/controllers/graphql_controller.rb','apps/api/app/graphql/demo_graph.rb','apps/web/app/api/graphql/route.ts']:
        actual=(ROOT/name).read_bytes()
        committed=subprocess.check_output(['git','show',spec['x-contract-sources']['source_commit']+':'+name],cwd=ROOT)
        assert actual==committed,name+' differs from reference source pin'
    for path,fragment in [('/graphql','post "/graphql"'),('/health','get "/health"')]:
        assert fragment in (ROOT/'apps/api/config/routes.rb').read_text()
        assert {entry['url'] for entry in spec['paths'][path]['servers']}=={'http://127.0.0.1:3108','http://127.0.0.1:3109'}
    assert set(spec['paths'])=={'/api/graphql','/graphql','/health'}
    assert spec['x-agent-interfaces']['mcp']['implemented'] is False
    assert spec['x-agent-interfaces']['webmcp']['implemented'] is False
    live_reads=0
    if live:
        origin=os.environ.get('SAVVY_API_ORIGIN','http://127.0.0.1:3108')
        assert origin in API_ORIGINS,'Unsupported loopback API origin'
        def request(query):
            req=urllib.request.Request(origin+'/graphql',data=json.dumps({'query':query}).encode(),headers={'Content-Type':'application/json','X-Demo-Role':'operator'})
            with urllib.request.urlopen(req,timeout=20) as response:return json.load(response)
        result=request('{__schema{queryType{fields{name}} mutationType{fields{name}}}}')
        assert not result.get('errors')
        actual={f['name'] for key in ['queryType','mutationType'] for f in result['data']['__schema'][key]['fields']}
        assert actual==set(fields),'Running schema differs from reference'
        query=next(o['request'] for o in operations if o['name']=='disclosureWorkspace')
        req=urllib.request.Request(origin+'/graphql',data=json.dumps(query).encode(),headers={'Content-Type':'application/json','X-Demo-Role':'advisor'})
        with urllib.request.urlopen(req,timeout=20) as response:result=json.load(response)
        assert not result.get('errors') and result['data']['disclosureWorkspace']['available']
        with urllib.request.urlopen(origin+'/health',timeout=10) as response:health=json.load(response)
        assert health['contract_version']==spec['info']['version']
        live_reads=3
    print(f'OpenAPI valid; {len(operations)} operations match SDL; {len(spec["x-command-examples"])} command examples validated; {live_reads} read-only live probes; no mutations sent.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--live',action='store_true')
    check(parser.parse_args().live)
