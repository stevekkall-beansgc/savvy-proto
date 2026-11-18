# Guarded synthetic database only. Root coordinates resets across suites.
ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class DisclosureGovernanceStressTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    @operator=Workbench.new(role:'operator'); @operator.seed!
    @service=DisclosureWorkbench.new(@operator)
    @service.bootstrap({},'stress-boot')
  end
  def override_method(object, name, implementation)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.singleton_class.remove_method(name)
  end
  def draft(rate,key)
    @service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields.merge('annual_rate'=>rate),'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Fictional stress review'},key)
  end
  def compare(id,key)
    @service.compare({'case_id'=>'advisor','policy_id'=>id,'baseline_run_id'=>'disclosure-run-v1'},key)
  end
  def review(role,id,decision,key)
    DisclosureWorkbench.new(Workbench.new(role:role)).review({'case_id'=>'advisor','comparison_id'=>id,'decision'=>decision,'reason'=>'Fictional stress review'},key)
  end
  def publication(policy,comparison)
    {'case_id'=>'advisor','policy_id'=>policy,'comparison_id'=>comparison}
  end
  def invoice_snapshot
    inv=BillingInvoice.find_by!(external_id:'disclosure-invoice-v1')
    [inv.attributes,BillingInvoiceLine.where(billing_invoice_id:inv.id).order(:id).map(&:attributes)]
  end
  def test_denial_supersedes_prior_approval_and_publication_does_not_assign
    initial=invoice_snapshot
    p=draft('33/2500','draft'); c=compare(p['policy_id'],'compare')
    assert_equal [100000,110000],c.values_at('old_amount_minor','new_amount_minor')
    original=@service.rows('fact').where("payload ? 'observation'").first
    newer=original.payload.fetch('observation').merge('id'=>'new-claim','amount_minor'=>1,'recorded_at'=>'2027-02-02T00:00:00Z')
    @service.store('fact',id:'new-claim',status:'accepted',payload:{'observation'=>newer},recorded_at:Time.iso8601(newer['recorded_at']))
    repeated=compare(p['policy_id'],'compare-after-new-evidence')
    assert_equal [100000,110000],repeated.values_at('old_amount_minor','new_amount_minor'), 'Comparison must use the frozen baseline manifest'
    %w[legal finance].each { |role| review(role,c['comparison_id'],'approve',"approve-#{role}") }
    review('legal',c['comparison_id'],'reject','reject-legal')
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { @service.publish(publication(p['policy_id'],c['comparison_id']),'publish-denied') }.code
    review('legal',c['comparison_id'],'approve','approve-legal-again')
    @service.publish(publication(p['policy_id'],c['comparison_id']),'publish')
    assert_equal initial,invoice_snapshot
    view=DisclosureReadModel.new(@operator).view('advisor',audience:'product')
    assert_equal 'disclosure-run-v1',view.dig('summary','selected_run_id')
    assert_equal 'disclosure-policy-v1',view.dig('summary','selected_policy_id')
    assert_equal initial,invoice_snapshot
  end
  def test_exact_pairing_replay_stale_binding_and_overlap
    p=draft('33/2500','draft'); q=draft('7/500','other-draft'); c=compare(p['policy_id'],'compare')
    assert_equal p,draft('33/2500','draft')
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { draft('3/250','draft') }.code
    %w[legal finance].each { |role| review(role,c['comparison_id'],'approve',"approve-#{role}") }
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { @service.publish(publication(q['policy_id'],c['comparison_id']),'wrong-pair') }.code
    override_method(@service,:implementation_hash,-> { 'changed-implementation' }) do
      assert_equal 'STALE_REVIEW',assert_raises(Economics::Error) { @service.publish(publication(p['policy_id'],c['comparison_id']),'stale-implementation') }.code
    end
    %w[fact run].each do |kind|
      original=@service.method(:get)
      replacement=lambda do |requested_kind,id|
        row=original.call(requested_kind,id)
        if requested_kind==kind
          fake=row.dup
          fake.define_singleton_method(:payload_hash) { 'changed-evidence-hash' }
          fake
        else
          row
        end
      end
      override_method(@service,:get,replacement) do
        assert_equal 'STALE_REVIEW',assert_raises(Economics::Error) { @service.publish(publication(p['policy_id'],c['comparison_id']),"stale-#{kind}") }.code
      end
    end
    @service.publish(publication(p['policy_id'],c['comparison_id']),'publish')
    input={'case_id'=>'advisor','policy_id'=>p['policy_id'],'subject_id'=>'disclosure-alder-household','effective_from'=>'2027-02-15','effective_to'=>'2027-03-01','reason'=>'Fictional overlap','supersedes_assignment_id'=>'disclosure-assignment-v1'}
    before=MedallionEvidence.count
    assert_includes %w[RULE_CONFLICT INVALID_INTERVAL],assert_raises(Economics::Error) { @service.assign(input,'partial-overlap') }.code
    assert_equal before,MedallionEvidence.count
    input['effective_from']='2027-02-01'
    result=@service.assign(input,'exact-replacement')
    assert_equal result,@service.assign(input,'exact-replacement')
  end
  def test_concurrent_identical_claims_produce_one_draft_and_conflicting_claim_fails
    input={'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields.merge('annual_rate'=>'33/2500'),'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Concurrent fictional review'}
    gate=Queue.new
    threads=2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          DisclosureWorkbench.new(Workbench.new(role:'operator')).save_policy(input,'concurrent-same-key')
        end
      end
    end
    2.times { gate << true }
    results=threads.map(&:value)
    assert_equal results.first,results.last
    assert_equal 1,@service.rows('policy').where(external_id:results.first.fetch('policy_id')).count
    assert_equal 1,DemoOperation.where(actor_id:'operator',operation:'disclosure_save_policy',idempotency_key:'concurrent-same-key').count
    altered=input.merge('policy'=>input['policy'].merge('annual_rate'=>'3/250'))
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { @service.save_policy(altered,'concurrent-same-key') }.code
  end

end
