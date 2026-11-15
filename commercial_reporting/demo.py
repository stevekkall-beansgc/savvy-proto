"""Run a small synthetic contract-to-reporting demonstration."""
import json
from .store import Store

def main():
    db = Store()
    source = {'document': 'Illustrative agreement; fee $120 per month and 20% of defined monthly revenue.', 'source_format': 'sample-json'}
    db.ingest('sample-contract-source', source)
    db.register_contract('sample-contract', 1, 'sample-contract-source', '2026-01-01', '2026-12-31', [
        {'clause_id': 'monthly-fee', 'mechanism': 'fixed_period_fee', 'amount_cents': 12000, 'display_text': 'A $120 monthly platform fee.'},
        {'clause_id': 'revenue-share', 'mechanism': 'basis_points_of_input', 'basis_key': 'monthly_revenue_cents', 'rate_bps': 2000, 'display_text': '20% of defined monthly revenue.'}])
    forecast = db.project('forecast-2026-11-13', '2026-11-13', '2026-11-01', '2026-11-30', [
        {'contract_id': 'sample-contract', 'version': 1, 'inputs': {'monthly_revenue_cents': 30000}}])
    db.ingest_event({'source':'sample-billing','event_id':'invoice-1','revision':1,'contract_id':'sample-contract','clause_id':'monthly-fee',
        'period_start':'2026-11-01','period_end':'2026-11-30','observed_on':'2026-12-01','currency':'USD','type':'invoice','state':'active','amount_cents':12000})
    actual = db.actuals('actuals-2026-12-01','2026-12-01')
    print(json.dumps({'projection': forecast, 'actuals': actual}, indent=2))

if __name__ == '__main__': main()
