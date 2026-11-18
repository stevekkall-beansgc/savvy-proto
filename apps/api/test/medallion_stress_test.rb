ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
class MedallionStressTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new; @operator.seed!; @operator.medallion.bootstrap({},'bootstrap')
    @finance=Workbench.new(role:'finance')
  end
  def run_case
    @operator.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'run')
  end
  def payment(status='confirmed')
    {'id'=>'pay','revision'=>1,'amount_minor'=>5000,'currency'=>'USD','debtor_id'=>'ria-harbor','creditor_id'=>'firm-demo','status'=>status,'observed_at'=>'2026-10-02T22:00:00Z'}
  end
  def args(run)
    {'case_id'=>'ria','payment_id'=>'pay','payment_revision'=>1,'run_id'=>run['id'],'output_id'=>'net','amount_minor'=>5000,'posting_period'=>'2026-10','reason'=>'Apply evidence'}
  end
  def test_source_conflict_pending_and_wrong_direction_fail_closed
    p=payment('pending'); @finance.medallion.record_payment({'case_id'=>'ria','payment'=>p},'record')
    error=assert_raises(Economics::Error) { @finance.medallion.record_payment({'case_id'=>'ria','payment'=>p.merge('amount_minor'=>6000)},'conflict') }
    assert_equal 'SOURCE_CONFLICT',error.code
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error) { @finance.medallion.apply_payment(args(run_case),'apply') }.code
    bad=payment.merge('id'=>'backwards','debtor_id'=>'firm-demo','creditor_id'=>'ria-harbor')
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { @finance.medallion.record_payment({'case_id'=>'ria','payment'=>bad},'bad') }.code
  end
  def test_parallel_applications_do_not_double_spend_evidence
    r=run_case; @finance.medallion.record_payment({'case_id'=>'ria','payment'=>payment},'record')
    ready=Queue.new; release=Queue.new
    threads=2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true; release.pop
          begin
            Workbench.new(role:'finance').medallion.apply_payment(args(r),"parallel-#{i}")
            'applied'
          rescue Economics::Error => e
            e.code
          end
        end
      end
    end
    2.times { ready.pop }; 2.times { release << true }
    assert_equal ['ALLOCATION_EXCEEDED','applied'],threads.map(&:value).sort
    assert_equal 1,MedallionEvidence.where(case_id:'ria',scenario_id:'baseline',kind:'application').count
  end
  def test_application_reversal_is_single_and_restores_due
    r=run_case; @finance.medallion.record_payment({'case_id'=>'ria','payment'=>payment},'record')
    a=@finance.medallion.apply_payment(args(r),'apply')
    @finance.medallion.reverse_application({'case_id'=>'ria','application_id'=>a['id'],'posting_period'=>'2026-10','reason'=>'Correct error'},'reverse')
    assert_equal 'ALREADY_REVERSED',assert_raises(Economics::Error) { @finance.medallion.reverse_application({'case_id'=>'ria','application_id'=>a['id'],'posting_period'=>'2026-10','reason'=>'Correct error'},'again') }.code
    row=@operator.medallion.get!('ria','baseline','run',r['id'])
    assert_equal '13000',@operator.medallion.projected_statement('ria','baseline',row)['balance_minor']
  end
end
