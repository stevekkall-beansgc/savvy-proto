"""Synthetic local reporting vertical slice; not a production ledger or scheduler."""
import hashlib
import json
import sqlite3
from datetime import date


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)


def day(value):
    if not isinstance(value, str) or date.fromisoformat(value).isoformat() != value:
        raise ValueError('Expected ISO date')
    return value


def integer(value, name, minimum=0):
    if type(value) is not int or value < minimum or value > 2**53-1:
        raise ValueError(f'{name} must be an integer from {minimum} to 2^53-1')
    return value


def identifier(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 200:
        raise ValueError('Expected a nonempty identifier')
    return value


def digest(obj):
    return hashlib.sha256(canonical(obj).encode()).hexdigest()


class Store:
    def __init__(self, path=':memory:'):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS raw_inputs (id TEXT PRIMARY KEY, payload TEXT NOT NULL, hash TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS contracts (contract_id TEXT NOT NULL, version INTEGER NOT NULL,
          effective_from TEXT NOT NULL, effective_to TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES raw_inputs(id),
          state TEXT NOT NULL, terms TEXT NOT NULL, terms_hash TEXT NOT NULL, PRIMARY KEY(contract_id,version));
        CREATE TABLE IF NOT EXISTS runs (run_id TEXT PRIMARY KEY, kind TEXT NOT NULL, as_of TEXT NOT NULL,
          input_hash TEXT NOT NULL, output TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS events (source TEXT NOT NULL, event_id TEXT NOT NULL, revision INTEGER NOT NULL,
          payload TEXT NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(source,event_id,revision));
        ''')

    def ingest(self, source_id, payload):
        """Retain the exact JSON-compatible input; existing IDs cannot be overwritten."""
        identifier(source_id)
        if not isinstance(payload, dict): raise ValueError('Input must be a JSON object')
        encoded = canonical(payload)
        previous = self.db.execute('SELECT hash FROM raw_inputs WHERE id=?', (source_id,)).fetchone()
        h = digest(payload)
        if previous and previous['hash'] != h: raise ValueError('Source ID already exists with different contents')
        with self.db:
            self.db.execute('INSERT OR IGNORE INTO raw_inputs VALUES (?,?,?)', (source_id, encoded, h))
        return h

    def register_contract(self, contract_id, version, source_id, effective_from, effective_to, clauses):
        identifier(contract_id); identifier(source_id); integer(version, 'version', 1)
        day(effective_from); day(effective_to)
        if effective_from > effective_to: raise ValueError('Invalid effective period')
        if not isinstance(clauses, list) or not clauses: raise ValueError('At least one clause required')
        seen = set(); supported = {'fixed_period_fee', 'basis_points_of_input'}; ready = True
        for c in clauses:
            if not isinstance(c, dict): raise ValueError('Clause must be an object')
            cid = identifier(c.get('clause_id'))
            if cid in seen: raise ValueError('Duplicate clause ID')
            seen.add(cid)
            if not isinstance(c.get('display_text'), str) or not c['display_text'].strip(): raise ValueError('Clause requires client-specific display text')
            mechanism = c.get('mechanism')
            if mechanism not in supported:
                ready = False
                continue
            if mechanism == 'fixed_period_fee': integer(c.get('amount_cents'), 'amount_cents')
            if mechanism == 'basis_points_of_input':
                integer(c.get('rate_bps'), 'rate_bps')
                identifier(c.get('basis_key'))
        content = {'contract_id': contract_id, 'version': version, 'source_id': source_id,
                   'effective_from': effective_from, 'effective_to': effective_to, 'clauses': clauses}
        h = digest(content); state = 'ready' if ready else 'review_required'
        old = self.db.execute('SELECT terms_hash FROM contracts WHERE contract_id=? AND version=?', (contract_id,version)).fetchone()
        if old:
            if old['terms_hash'] != h: raise ValueError('Contract version is immutable')
            return state
        if not self.db.execute('SELECT 1 FROM raw_inputs WHERE id=?',(source_id,)).fetchone(): raise ValueError('Unknown source')
        # New versions may supersede previous versions, but are not auto-selected.
        with self.db:
            self.db.execute('INSERT INTO contracts VALUES (?,?,?,?,?,?,?,?)',
                            (contract_id,version,effective_from,effective_to,source_id,state,canonical(content),h))
        return state

    def _save_run(self, run_id, kind, as_of, request, result):
        identifier(run_id); day(as_of)
        h = digest(request)
        old = self.db.execute('SELECT * FROM runs WHERE run_id=?',(run_id,)).fetchone()
        if old:
            if old['kind'] != kind or old['input_hash'] != h: raise ValueError('Run ID already used for different inputs')
            return json.loads(old['output'])
        with self.db:
            self.db.execute('INSERT INTO runs VALUES (?,?,?,?,?)',(run_id,kind,as_of,h,canonical(result)))
        return result

    def project(self, run_id, as_of, period_start, period_end, selections):
        day(as_of); day(period_start); day(period_end)
        if period_start > period_end: raise ValueError('Invalid period')
        if not isinstance(selections, list) or not selections: raise ValueError('Select contracts')
        rows=[]; seen=set()
        for s in selections:
            key=(identifier(s.get('contract_id')),integer(s.get('version'),'version',1))
            if key[0] in seen: raise ValueError('One version per contract per run')
            seen.add(key[0])
            contract=self.db.execute('SELECT * FROM contracts WHERE contract_id=? AND version=?',key).fetchone()
            if not contract: raise ValueError('Unknown contract version')
            if contract['state'] != 'ready': raise ValueError('Contract requires review before calculation')
            if contract['effective_from'] > period_start or contract['effective_to'] < period_end: raise ValueError('Version does not cover full reporting period')
            inputs=s.get('inputs', {})
            if not isinstance(inputs, dict): raise ValueError('inputs must be an object')
            terms=json.loads(contract['terms'])
            for clause in terms['clauses']:
                if clause['mechanism'] == 'fixed_period_fee': amount=clause['amount_cents']
                else:
                    basis=integer(inputs.get(clause['basis_key']),'basis input')
                    amount=(basis * clause['rate_bps'] + 5000)//10000
                    integer(amount,'calculated amount')
                rows.append({'contract_id':key[0], 'contract_version':key[1], 'clause_id':clause['clause_id'],
                    'display_text':clause['display_text'], 'mechanism':clause['mechanism'], 'amount_cents':amount,
                    'period_start':period_start,'period_end':period_end,'as_of':as_of,'currency':'USD',
                    'classification':'projected','terms_hash':contract['terms_hash'], 'source_id':contract['source_id']})
        req={'kind':'projection','as_of':as_of,'period_start':period_start,'period_end':period_end,'selections':selections}
        return self._save_run(run_id,'projection',as_of,req,{'run_id':run_id,'rows':rows})

    def ingest_event(self, event):
        """Append source revisions; credit and void records do not become cash."""
        if not isinstance(event,dict): raise ValueError('Event must be an object')
        source=identifier(event.get('source')); eid=identifier(event.get('event_id')); revision=integer(event.get('revision'),'revision',1)
        identifier(event.get('contract_id')); identifier(event.get('clause_id'))
        day(event.get('period_start')); day(event.get('period_end')); day(event.get('observed_on'))
        if event['period_start'] > event['period_end']: raise ValueError('Invalid event period')
        if event.get('currency') != 'USD': raise ValueError('Only USD supported')
        if event.get('type') not in ('invoice','credit','cash'): raise ValueError('Unknown event type')
        if event.get('state') not in ('active','voided'): raise ValueError('Unknown event state')
        integer(event.get('amount_cents'),'amount_cents')
        h=digest(event)
        old=self.db.execute('SELECT hash FROM events WHERE source=? AND event_id=? AND revision=?',(source,eid,revision)).fetchone()
        if old and old['hash'] != h: raise ValueError('Conflicting event revision')
        with self.db:
            self.db.execute('INSERT OR IGNORE INTO events VALUES (?,?,?,?,?)',(source,eid,revision,canonical(event),h))
        return h

    def actuals(self, run_id, as_of):
        day(as_of)
        # Select latest revision visible on the as-of date, preserving prior history.
        versions=self.db.execute('SELECT * FROM events ORDER BY source,event_id,revision').fetchall()
        latest={}
        for row in versions:
            e=json.loads(row['payload'])
            if e['observed_on'] <= as_of: latest[(e['source'],e['event_id'])]=e
        rows=[{**e,'classification': 'realized_billing' if e['type'] in ('invoice','credit') else 'cash_collection',
               'signed_amount_cents': (0 if e['state']=='voided' else -e['amount_cents'] if e['type']=='credit' else e['amount_cents'])}
              for e in latest.values()]
        req={'kind':'actuals','as_of':as_of,'events':rows}
        return self._save_run(run_id,'actuals',as_of,req,{'run_id':run_id,'as_of':as_of,'rows':rows})
