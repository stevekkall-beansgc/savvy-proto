import unittest
from commercial_reporting.store import Store

class CommercialReportingTest(unittest.TestCase):
    def setUp(self):
        self.s=Store()
        self.s.ingest('source-1', {'raw_text':'Fictional contract', 'unmapped': {'any':'data'}})
        self.terms=[{'clause_id':'base','mechanism':'fixed_period_fee','amount_cents':12000,'display_text':'Your monthly platform fee is $120.'},
                    {'clause_id':'share','mechanism':'basis_points_of_input','basis_key':'billable_revenue_cents','rate_bps':2000,'display_text':'20% of billable revenue.'}]
        self.s.register_contract('contract-1',1,'source-1','2026-01-01','2026-12-31',self.terms)
    def test_projection_lineage_and_retry(self):
        selection=[{'contract_id':'contract-1','version':1,'inputs':{'billable_revenue_cents':30000}}]
        first=self.s.project('run-1','2026-11-13','2026-11-01','2026-11-30',selection)
        self.assertEqual([r['amount_cents'] for r in first['rows']],[12000,6000])
        self.assertEqual(first['rows'][1]['display_text'],'20% of billable revenue.')
        self.assertEqual(first,self.s.project('run-1','2026-11-13','2026-11-01','2026-11-30',selection))
        with self.assertRaises(ValueError): self.s.project('run-1','2026-11-14','2026-11-01','2026-11-30',selection)
    def test_unknown_and_immutable(self):
        self.assertEqual(self.s.register_contract('unknown',1,'source-1','2026-01-01','2026-12-31', [{'clause_id':'special','mechanism':'new_rule','display_text':'Special term'}]),'review_required')
        with self.assertRaises(ValueError): self.s.project('x','2026-11-13','2026-11-01','2026-11-30',[{'contract_id':'unknown','version':1}])
        with self.assertRaises(ValueError): self.s.register_contract('contract-1',1,'source-1','2026-01-01','2026-12-31',[{**self.terms[0],'amount_cents':1}])
        with self.assertRaises(ValueError): self.s.ingest('source-1',{'different':True})
    def test_actual_revision_cash_and_credits(self):
        base={'source':'demo','event_id':'1','revision':1,'contract_id':'contract-1','clause_id':'base','period_start':'2026-11-01','period_end':'2026-11-30','observed_on':'2026-11-14','currency':'USD','type':'invoice','state':'active','amount_cents':12000}
        self.s.ingest_event(base); self.s.ingest_event(base)
        self.s.ingest_event({**base,'event_id':'2','type':'cash','amount_cents':7000})
        self.s.ingest_event({**base,'event_id':'3','type':'credit','amount_cents':500})
        self.s.ingest_event({**base,'revision':2,'state':'voided','observed_on':'2026-11-16'})
        before=self.s.actuals('before','2026-11-15')['rows']; after=self.s.actuals('after','2026-11-16')['rows']
        self.assertEqual([r['signed_amount_cents'] for r in before],[12000,7000,-500])
        self.assertEqual([r['signed_amount_cents'] for r in after],[0,7000,-500])
        self.assertEqual(after[1]['classification'],'cash_collection')
        with self.assertRaises(ValueError): self.s.ingest_event({**base,'amount_cents':2})
    def test_reject_missing_basis_and_uncovered_period(self):
        with self.assertRaises(ValueError): self.s.project('a','2026-11-13','2026-11-01','2026-11-30',[{'contract_id':'contract-1','version':1}])
        with self.assertRaises(ValueError): self.s.project('a','2026-11-13','2026-12-01','2027-01-31',[{'contract_id':'contract-1','version':1,'inputs':{'billable_revenue_cents':0}}])

if __name__=='__main__': unittest.main()
