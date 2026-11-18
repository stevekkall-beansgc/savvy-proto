ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
class DisclosureWorkbenchTest < Minitest::Test
  def setup
    SyntheticReset.call
    @w=Workbench.new(role:'operator'); @w.seed!
    @service=DisclosureWorkbench.new(@w)
  end
  def test_bootstrap_native_invoice_and_scoped_reads
    result=@service.bootstrap({},'disclosure-test-bootstrap')
    assert_equal result,@service.bootstrap({},'disclosure-test-bootstrap')
    invoice=BillingInvoice.find_by!(external_id:'disclosure-invoice-v1')
    assert_equal 100000,invoice.amount_minor
    assert_equal [40000,60000],BillingInvoiceLine.where(billing_invoice_id:invoice.id).pluck(:amount_minor).sort
    view=DisclosureReadModel.new(@w).view('advisor',audience:'client')
    assert_equal true,view['available']
    assert_equal [100000,60000,40000],view.dig('sections','billing').map { |r| r['amount_minor'] }
    assert_raises(Economics::Error) { DisclosureReadModel.new(Workbench.new(role:'ria')).view('advisor',audience:'client') }
    assert_raises(Economics::Error) { DisclosureReadModel.new(Workbench.new(role:'advisor')).view('advisor',audience:'product') }
  end
  def test_exact_review_assignment_and_no_silent_rebill
    @service.bootstrap({},'bootstrap')
    p=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields.merge('annual_rate'=>'33/2500'),'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review a fictional rate'},'save')
    c=@service.compare({'case_id'=>'advisor','policy_id'=>p['policy_id'],'baseline_run_id'=>'disclosure-run-v1'},'compare')
    assert_equal [100000,110000],c.values_at('old_amount_minor','new_amount_minor')
    pub={'case_id'=>'advisor','policy_id'=>p['policy_id'],'comparison_id'=>c['comparison_id']}
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { @service.publish(pub,'early-publish') }.code
    %w[legal finance].each do |role|
      DisclosureWorkbench.new(Workbench.new(role:role)).review({'case_id'=>'advisor','comparison_id'=>c['comparison_id'],'decision'=>'approve','reason'=>'Reviewed exact fictional comparison'},"review-#{role}")
    end
    @service.publish(pub,'publish')
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
    assign={'case_id'=>'advisor','policy_id'=>p['policy_id'],'subject_id'=>'disclosure-alder-household','effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review replacement','supersedes_assignment_id'=>'disclosure-assignment-v1'}
    @service.assign(assign,'assign')
    result=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-28T23:59:59Z'},'evaluate')
    assert_equal [110000,true,false],result.values_at('amount_minor','correction_required','invoice_reissued')
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
    view=DisclosureReadModel.new(@w).view('advisor',audience:'product')
    assert_equal [100000,60000,40000,110000],view.dig('sections','billing').map { |row| row['amount_minor'] }
  end

  def test_hourly_policy_lifecycle_uses_frozen_timesheet_and_preserves_invoice
    @service.bootstrap({},'bootstrap-hourly')
    fields={'basis'=>'hourly','cadence'=>'monthly','annual_rate'=>nil,'minimum_minor'=>nil,'fixed_amount_minor'=>nil,'hourly_rate_minor'=>25000,'optional_service'=>'none'}
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-option-hourly','policy'=>fields,'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review hourly rate'},'save-hourly')
    cmp=@service.compare({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'baseline_run_id'=>'disclosure-option-run-hourly'},'compare-hourly')
    assert_equal [70000,87500],cmp.values_at('old_amount_minor','new_amount_minor')
    %w[legal finance].each { |role| DisclosureWorkbench.new(Workbench.new(role:role)).review({'case_id'=>'advisor','comparison_id'=>cmp['comparison_id'],'decision'=>'approve','reason'=>'Exact comparison reviewed'},"hourly-#{role}") }
    @service.publish({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'comparison_id'=>cmp['comparison_id']},'publish-hourly')
    @service.assign({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'subject_id'=>'disclosure-alder-household','effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Approve assignment','supersedes_assignment_id'=>'disclosure-assignment-v1'},'assign-hourly')
    early=assert_raises(Economics::Error) { @service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-28T23:59:59Z'},'hourly-early') }
    assert_equal 'INCOMPLETE_SOURCE',early.code
    result=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-03-02T23:59:59Z'},'evaluate-hourly')
    assert_equal [87500,true,false],result.values_at('amount_minor','correction_required','invoice_reissued')
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
  end

  def test_late_eligibility_revision_changes_only_later_as_known_run
    @service.bootstrap({},'bootstrap-revision')
    row=@w.medallion.get!('advisor','disclosure_2027','fact','disclosure-a-private')
    payload=Economics::Canonical.copy(row.payload)
    payload['revision']=2; payload['observation']['revision']=2; payload['observation']['eligible']=true
    payload['observation']['recorded_at']='2027-02-20T00:00:00Z'
    payload['source_artifact_id']='disclosure-revised-valuation-artifact'
    recorded=Time.iso8601('2027-02-20T00:00:00Z'); bytes='synthetic revised valuation'
    artifact=@w.medallion.store!('advisor','disclosure_2027','artifact',id:payload['source_artifact_id'],status:'retained',payload:{'synthetic'=>true,'sha256'=>Digest::SHA256.hexdigest(bytes)},bytes:bytes,recorded_at:recorded)
    delivery=@w.medallion.store!('advisor','disclosure_2027','delivery',id:'disclosure-revised-valuation-delivery',status:'accepted',payload:{'synthetic'=>true,'artifact_id'=>artifact.external_id},parent:artifact,recorded_at:recorded)
    @w.medallion.store!('advisor','disclosure_2027','fact',id:row.external_id,revision:2,status:'accepted',payload:payload,parent:delivery,recorded_at:recorded)
    before=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-19T23:59:59Z'},'before-revision')
    after=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-21T00:00:00Z'},'after-revision')
    assert_equal [100000,115000],[before['amount_minor'],after['amount_minor']]
    assert_equal [false,true],[before['correction_required'],after['correction_required']]
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
  end

  def test_daily_balance_policy_review_uses_28_day_frozen_manifest
    @service.bootstrap({},'bootstrap-adb')
    fields={'basis'=>'average_daily_balance','cadence'=>'monthly','annual_rate'=>'33/2500','minimum_minor'=>nil,'fixed_amount_minor'=>nil,'optional_service'=>'none'}
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-option-average-daily-balance','policy'=>fields,'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review daily-balance rate'},'save-adb')
    cmp=@service.compare({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'baseline_run_id'=>'disclosure-option-run-average-daily-balance'},'compare-adb')
    assert_equal [110000,121000],cmp.values_at('old_amount_minor','new_amount_minor')
    %w[legal finance].each { |role| DisclosureWorkbench.new(Workbench.new(role:role)).review({'case_id'=>'advisor','comparison_id'=>cmp['comparison_id'],'decision'=>'approve','reason'=>'Exact comparison reviewed'},"adb-#{role}") }
    @service.publish({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'comparison_id'=>cmp['comparison_id']},'publish-adb')
    @service.assign({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'subject_id'=>'disclosure-alder-household','effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Approve assignment','supersedes_assignment_id'=>'disclosure-assignment-v1'},'assign-adb')
    early=assert_raises(Economics::Error) { @service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-28T23:59:59Z'},'adb-early') }
    assert_equal 'INCOMPLETE_SOURCE',early.code
    run=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-03-02T23:59:59Z'},'evaluate-adb')
    assert_equal [121000,true,false],run.values_at('amount_minor','correction_required','invoice_reissued')
    row=@w.medallion.get!('advisor','disclosure_2027','fact','disclosure-adb-a-01')
    payload=Economics::Canonical.copy(row.payload); payload['revision']=2; payload['observation']['revision']=2
    payload['observation']['amount_minor']=88000000; payload['observation']['recorded_at']='2027-03-03T00:00:00Z'
    payload['source_artifact_id']='disclosure-adb-revised-artifact'; recorded=Time.iso8601('2027-03-03T00:00:00Z'); bytes='synthetic revised daily observation'
    artifact=@w.medallion.store!('advisor','disclosure_2027','artifact',id:payload['source_artifact_id'],status:'retained',payload:{'synthetic'=>true,'sha256'=>Digest::SHA256.hexdigest(bytes)},bytes:bytes,recorded_at:recorded)
    delivery=@w.medallion.store!('advisor','disclosure_2027','delivery',id:'disclosure-adb-revised-delivery',status:'accepted',payload:{'synthetic'=>true,'artifact_id'=>artifact.external_id},parent:artifact,recorded_at:recorded)
    @w.medallion.store!('advisor','disclosure_2027','fact',id:row.external_id,revision:2,status:'accepted',payload:payload,parent:delivery,recorded_at:recorded)
    later=@service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-03-04T00:00:00Z'},'adb-revised')
    assert_equal 122100,later['amount_minor']
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
  end

  def test_recomparison_updates_one_request_and_retains_previous_evidence
    @service.bootstrap({},'queue-bootstrap')
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields.merge('annual_rate'=>'33/2500'),'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review the same request again'},'queue-draft')
    input={'case_id'=>'advisor','policy_id'=>draft.fetch('policy_id'),'baseline_run_id'=>'disclosure-run-v1'}
    first=@service.compare(input,'queue-compare-first')
    latest=@service.compare(input,'queue-compare-latest')
    view=DisclosureReadModel.new(Workbench.new(role:'operator')).view('advisor',audience:'product',limit:100)
    changes=view.fetch('sections').fetch('changes').select { |r| r['policy_id']==draft.fetch('policy_id') }
    assert_equal 1,changes.size
    assert_equal latest.fetch('comparison_id'),changes.first.fetch('comparison_id')
    assert @service.get('comparison',first.fetch('comparison_id'))
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
  end

end

class DisclosureEconomicCorrectionTest < Minitest::Test
  def setup
    SyntheticReset.call
    @w=Workbench.new(role:'operator'); @w.seed!
    @service=DisclosureWorkbench.new(@w); @service.bootstrap({},'economic-bootstrap')
    @policy=@service.get('policy','disclosure-policy-v1'); @original=@service.get('run','disclosure-run-v1')
    @result=Economics::Canonical.copy(@original.payload.fetch('result'))
  end
  def detail(result,id) = result.fetch('details').find { |item| item['id']==id }
  def correction(result) = @service.correction_required?(result,@policy,@original)
  def test_line_identity_amount_and_order
    refute correction(@result)
    @result['details'].reverse!; refute correction(@result)
    detail(@result,'line_a')['assessed_minor']+=10000; detail(@result,'line_b')['assessed_minor']-=10000
    assert correction(@result)
    detail(@result,'line_a')['assessed_minor']-=9999; detail(@result,'line_b')['assessed_minor']+=9999
    assert correction(@result)
    detail(@result,'line_a')['assessed_minor']=0; detail(@result,'line_b')['assessed_minor']=100000
    assert correction(@result)
    detail(@result,'charge')['assessed_minor']=100001; detail(@result,'line_b')['assessed_minor']=100001
    assert correction(@result)
    assert_equal [40000,60000],BillingInvoiceLine.where(billing_invoice_id:BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').id).pluck(:amount_minor).sort
  end
  def test_equal_total_nonallocated_output_still_requires_correction
    policy=@service.get('policy','disclosure-option-hourly')
    result=Economics::Canonical.copy(@service.get('run','disclosure-option-run-hourly').payload.fetch('result'))
    detail(result,'charge')['assessed_minor']=100000
    assert @service.correction_required?(result,policy,@original)
  end
  def test_unexpected_billable_terminal_fails_closed_but_intermediate_does_not
    extra=Economics::Canonical.copy(detail(@result,'line_a'))
    extra['id']='line_extra'; extra['assessed_minor']=1
    @result.fetch('details') << extra
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { correction(@result) }.code
    extra['role']='intermediate'
    refute correction(@result)
  end
  def test_invalid_allocations_fail_closed_and_economic_metadata_changes
    detail(@result,'line_a')['assessed_minor']=nil
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { correction(@result) }.code
    @result=Economics::Canonical.copy(@original.payload.fetch('result'))
    detail(@result,'line_a')['assessed_minor']+=1
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { correction(@result) }.code
    %w[payer payee unit basis output_class role].each do |field|
      @result=Economics::Canonical.copy(@original.payload.fetch('result'))
      detail(@result,'line_a')[field]=nil
      assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { correction(@result) }.code,field
    end
    @result=Economics::Canonical.copy(@original.payload.fetch('result'))
    detail(@result,'line_a')['currency']='EUR'; assert correction(@result)
    @result=Economics::Canonical.copy(@original.payload.fetch('result'))
    detail(@result,'charge')['payer']='other'; assert correction(@result)
    @result=Economics::Canonical.copy(@original.payload.fetch('result'))
    detail(@result,'line_b')['interval']['end_exclusive']='2027-02-28'; assert correction(@result)
  end
  def test_assign_and_historical_assignment_reject_outside_policy_window
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields,'effective_from'=>'2027-02-02','effective_to'=>nil,'reason'=>'Future policy'},'bad-window-save')
    input={'case_id'=>'advisor','policy_id'=>draft['policy_id'],'subject_id'=>'disclosure-alder-household','effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Out of range','supersedes_assignment_id'=>'disclosure-assignment-v1'}
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @service.assign(input,'bad-window-assign') }.code
    [nil,'2027-02-30','2027-03-02'].each_with_index do |value,index|
      bad=input.merge('effective_to'=>value)
      assert_raises(Economics::Error) { @service.assign(bad,"bad-end-#{index}") }
    end
    assert_equal 'VALIDATION_ERROR',assert_raises(Economics::Error) { @service.assign(input.except('effective_to'),'missing-end') }.code
    policy=@service.get('policy',draft['policy_id'])
    @service.store('assignment',id:'historical-bad-assignment',status:'published',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>DisclosureWorkbench::SUBJECT,'supersedes_assignment_id'=>'disclosure-assignment-v1'},parent:policy,recorded_at:Time.iso8601('2027-02-01T00:00:00Z'),schedule_version:2)
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @service.evaluate({'case_id'=>'advisor','knowledge_cutoff'=>'2027-02-28T23:59:59Z'},'historical-bad-evaluate') }.code
  end
  def test_policy_window_is_half_open_and_comparison_is_unrestricted
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields,'effective_from'=>'2027-02-02','effective_to'=>nil,'reason'=>'Future start'},'window-save')
    @service.compare({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'baseline_run_id'=>'disclosure-run-v1'},'window-compare')
    policy=@service.get('policy',draft['policy_id'])
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @service.policy_window!(policy,'2027-02-01','2027-03-01') }.code
    @service.policy_window!(policy,'2027-02-02','2027-03-01')
    finite=@service.get('policy','disclosure-policy-v1')
    @service.policy_window!(finite,'2027-02-01','2027-03-01')
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @service.policy_window!(finite,'2027-02-01','2027-03-02') }.code
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @service.policy_window!(finite,'2027-02-01',nil) }.code
  end
end
