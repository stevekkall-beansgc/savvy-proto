ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
require 'timeout'
class MedallionReadBoundsTest < Minitest::Test
  def setup
    SyntheticReset.call
    @w=Workbench.new(role:'operator'); @w.seed!
    @w.medallion.bootstrap({},'read-bounds-bootstrap')
    @w.medallion.evaluate_case({'case_id'=>'advisor','policy_id'=>'advisor-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'read-bounds-run')
  end
  def test_pages_are_bounded_and_selected_run_and_statement_are_independent
    full=@w.medallion.view(workspace:'internal',case_id:'advisor',limit:100)
    run=full.fetch('run').fetch('id')
    first=@w.medallion.view(workspace:'internal',case_id:'advisor',run_id:run,limit:1,offset:0)
    second=@w.medallion.view(workspace:'internal',case_id:'advisor',run_id:run,limit:1,offset:1)
    assert_equal run,first.dig('run','id')
    assert_equal full['statement']['balance_minor'],first['statement']['balance_minor']
    %w[runs comparisons reviews events payments payment_applications assignments statements].each { |k| assert_operator first.fetch(k).size,:<=,1 }
    assert_operator first['policies'].size,:<=,2 # The applied policy is retained outside the page.
    assert first['policies'].any? { |p| p['id']==full.dig('terms').find { |t| t['status']=='applied' }['policy_id'] }
    assert_equal 1,first.dig('page','run','limit')
    assert_equal 1,second.dig('page','run','offset')
    assert_empty(first['runs'].map { |r| r['id'] } & second['runs'].map { |r| r['id'] })
    assert_raises(Economics::Error) { @w.medallion.view(workspace:'internal',case_id:'advisor',limit:101) }
  end
  def test_queue_filters_before_paging_and_loads_exact_linked_reviews
    service=@w.medallion
    base=service.source('advisor','baseline','policy').find_by!(external_id:'advisor-policy-v1')
    payload=base.payload.merge('base_id'=>base.external_id,'base_hash'=>base.payload_hash,'reason'=>'Synthetic review')
    oldest=service.store!('advisor','baseline','policy',id:'queue-oldest',status:'draft',payload:payload)
    110.times { |i| service.store!('advisor','baseline','policy',id:"queue-draft-#{i}",status:'draft',payload:payload) }
    110.times { |i| service.store!('advisor','baseline','policy',id:"queue-published-#{i}",status:'published',payload:payload) }
    comparison=service.store!('advisor','baseline','comparison',id:'queue-comparison',status:'completed',parent:oldest,payload:{'proposed_policy_id'=>oldest.external_id,'baseline_policy_id'=>base.external_id})
    %w[legal finance].each { |role| service.store!('advisor','baseline','review',id:"queue-review-#{role}",status:'approved',parent:oldest,payload:{'policy_id'=>oldest.external_id,'comparison_id'=>comparison.external_id,'role'=>role,'decision'=>'approved_for_demo'}) }
    sql=[]
    listener=ActiveSupport::Notifications.subscribe('sql.active_record') { |_name,_start,_finish,_id,payload| sql << payload[:sql] }
    first=service.view(workspace:'internal',case_id:'advisor',limit:50,offset:0)['request_queue']
    ActiveSupport::Notifications.unsubscribe(listener)
    assert sql.any? { |query| query.match?(/FROM \(.*UNION ALL.*\) queue ORDER BY id DESC LIMIT 50 OFFSET 0/i) }, 'Pending queue is filtered and limited by SQL'
    last=service.view(workspace:'internal',case_id:'advisor',limit:50,offset:100)['request_queue']
    assert_operator first['total'],:>=,111
    assert_operator first['policies'].size,:<=,50
    assert last['policies'].any? { |row| row['id']=='queue-oldest' }
    assert last['comparisons'].any? { |row| row['id']=='queue-comparison' }
    assert_equal %w[finance legal],last['reviews'].select { |row| row['comparison_id']=='queue-comparison' }.map { |row| row['role'] }.sort
    assert last['base_policies'].any? { |row| row['id']==base.external_id }
    assert_empty first['policies'].map { |row| row['id'] } & last['policies'].map { |row| row['id'] }
  end
  def test_history_queries_apply_sql_limit_before_loading
    sql=[]
    listener=ActiveSupport::Notifications.subscribe('sql.active_record') { |_name,_start,_finish,_id,payload| sql << payload[:sql] }
    result=@w.medallion.view(workspace:'internal',case_id:'advisor')
    assert_equal 50,result.dig('page','event','limit')
    evidence_selects=sql.select { |query| query.match?(/SELECT .*medallion_evidence.*LIMIT/i) && query.match?(/\bLIMIT\b/i) }
    assert evidence_selects.any?, 'history is limited by SQL before materialization'
  ensure
    ActiveSupport::Notifications.unsubscribe(listener) if listener
  end
  def test_independent_read_keeps_snapshot_during_concurrent_commit
    sample=@w.medallion.source('advisor','baseline','run').first!
    before=@w.medallion.source('advisor','baseline','run').count
    probe=Module.new do
      define_method(:rows) do |kind|
        if kind=='run' && !@snapshot_probed
          @snapshot_probed=true
          @before_commit=relation('run').count
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              copy=sample.dup
              copy.external_id='concurrent-snapshot-run'
              copy.save!
            end
          end.value
          @after_commit=relation('run').count
        end
        super(kind)
      end
    end
    presenter=MedallionPresenter.new(@w)
    presenter.singleton_class.prepend(probe)
    presenter.view(workspace:'internal',case_id:'advisor',limit:1)
    assert_equal before,presenter.instance_variable_get(:@before_commit)
    assert_equal before,presenter.instance_variable_get(:@after_commit)
    assert_equal before+1,@w.medallion.source('advisor','baseline','run').count
  end
  def test_read_does_not_wait_for_scope_writer_lock
    ready=Queue.new; release=Queue.new
    writer=Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        DemoScope.transaction do
          DemoScope.where(**@w.scope).lock.first!
          ready << true
          release.pop
        end
      end
    end
    ready.pop
    result=Timeout.timeout(5) { @w.medallion.view(workspace:'internal',case_id:'advisor',limit:1) }
    assert result['run']
  ensure
    release << true if release
    writer&.join
  end
end
