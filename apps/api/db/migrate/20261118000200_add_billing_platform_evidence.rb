class AddBillingPlatformEvidence < ActiveRecord::Migration[8.0]
  def up
    old="kind IN ('artifact','delivery','fact','policy','assignment','comparison','review','publication','event','event_review','payment','application','application_reversal','run','statement','period_lock','funding','coverage_right','receipt','receipt_allocation','netting_authority','receipt_reversal','funding_reversal','adjustment_intent')"
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_evidence_kind'
    execute "ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_evidence_kind CHECK (#{old} OR (scenario_id='billing_platform' AND kind IN ('source','normalized','normalization','policy_review','policy_publication','calculation','document','correction_proposal','correction_review','correction_issue','period_close')))"
    status="status IN ('retained','accepted','draft','approved','rejected','published','confirmed','pending','reversed','completed','blocked','sealed','locked')"
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_evidence_status'
    execute "ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_evidence_status CHECK (#{status} OR (scenario_id='billing_platform' AND status IN ('active','quarantined','issued','closed','proposed','unchanged')))"
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Retain evidence; restore the prior database for rollback'
  end
end
