class AddAdjustmentIntents < ActiveRecord::Migration[8.0]
  def up
    remove_check_constraint :medallion_evidence, name: 'medallion_evidence_kind'
    add_check_constraint :medallion_evidence, "kind IN ('artifact','delivery','fact','policy','assignment','comparison','review','publication','event','event_review','payment','application','application_reversal','run','statement','period_lock','funding','coverage_right','receipt','receipt_allocation','netting_authority','receipt_reversal','funding_reversal','adjustment_intent')", name: 'medallion_evidence_kind'
  end
  def down
    remove_check_constraint :medallion_evidence, name: 'medallion_evidence_kind'
    add_check_constraint :medallion_evidence, "kind IN ('artifact','delivery','fact','policy','assignment','comparison','review','publication','event','event_review','payment','application','application_reversal','run','statement','period_lock','funding','coverage_right','receipt','receipt_allocation','netting_authority','receipt_reversal','funding_reversal')", name: 'medallion_evidence_kind'
  end
end
