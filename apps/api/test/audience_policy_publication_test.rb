ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class AudiencePolicyPublicationTest < Minitest::Test
  QUERY = 'mutation($action:MedallionCommand!,$input:JSON!,$key:String!){medallionCommand(action:$action,input:$input,idempotencyKey:$key){data errors{code message}}}'

  def test_api_policy_lifecycle_remains_usable_after_client_publication
    SyntheticReset.call
    operator=Workbench.new
    operator.seed!
    operator.medallion.bootstrap({},'publication-bootstrap')
    operator.medallion.evaluate_case({'case_id'=>'advisor','policy_id'=>'advisor-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'publication-run')
    AudienceReadModel.new(operator).refresh!('advisor')
    before=AudienceReadModel.new(operator).summary('advisor')
    base=operator.medallion.policy!('advisor','baseline','advisor-policy-v1')
    command=lambda do |role,action,input|
      response=WorkbenchSchema.execute(QUERY,variables:{'action'=>action,'input'=>input.merge('case_id'=>'advisor'),'key'=>"publication-#{action}-#{role}"},context:{workbench:Workbench.new(role:role)}).to_h
      assert_nil response['errors']
      result=response.dig('data','medallionCommand')
      assert_empty result.fetch('errors'),result.inspect
      result.fetch('data')
    end
    draft=command.call('operator','SAVE_POLICY_VERSION',{
      'base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,
      'policy'=>base.payload.fetch('policy'),'rates'=>[{'id'=>'rate_s80','numerator'=>82,'denominator'=>100}],
      'reason'=>'Check policy lifecycle alongside read publications'})
    comparison=command.call('operator','COMPARE_POLICIES',{
      'baseline_policy_id'=>base.external_id,'proposed_policy_id'=>draft.fetch('id'),
      'knowledge_cutoff'=>'2026-10-02T23:00:00Z'})
    %w[legal finance].each do |role|
      command.call(role,'REVIEW_POLICY',{'policy_id'=>draft.fetch('id'),'comparison_id'=>comparison.fetch('id'),
        'decision'=>'approved_for_demo','document_ref'=>{'system'=>'mock_clm','document_id'=>'publication-review','version'=>'v1','status'=>'reviewed_for_demo'}})
    end
    command.call('finance','PUBLISH_POLICY',{'policy_id'=>draft.fetch('id'),'comparison_id'=>comparison.fetch('id'),'effective_from'=>'2026-09-01'})
    publications=operator.medallion.source('advisor','baseline','publication')
    assert publications.where("payload->>'projection_type' = 'audience/v1'").exists?
    assert publications.where("payload->>'policy_id' = ?",draft.fetch('id')).exists?
    after=AudienceReadModel.new(operator).summary('advisor')
    assert_equal before.dig('run','id'),after.dig('run','id'),'Publication must not assign or reassess billing'
    assert_equal before.dig('run','summary'),after.dig('run','summary')
  end
end
