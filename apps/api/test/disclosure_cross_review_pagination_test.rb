ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class DisclosureCrossReviewPaginationTest < Minitest::Test
  def test_queue_pagination_does_not_erase_financial_context
    SyntheticReset.call
    workbench=Workbench.new(role:'operator'); workbench.seed!
    service=DisclosureWorkbench.new(workbench); service.bootstrap({},'cross-review-bootstrap')
    policy=service.get('policy','disclosure-policy-v1')
    110.times do |index|
      service.store('policy',id:"cross-review-draft-#{index}",status:'draft',payload:{'base_policy_id'=>policy.external_id,'baseline_run_id'=>'disclosure-run-v1'},parent:policy)
    end
    reader=DisclosureReadModel.new(workbench)
    sql=[]
    listener=ActiveSupport::Notifications.subscribe('sql.active_record') { |_name,_start,_finish,_id,payload| sql << payload[:sql] }
    first=reader.view('advisor',audience:'product',limit:100,offset:0,page_changes:true)
    ActiveSupport::Notifications.unsubscribe(listener)
    assert sql.any? { |query| query.match?(/FROM \(.*UNION ALL.*\) changes ORDER BY kind_order, sort_id LIMIT/i) }, 'Request pages are limited in SQL before loading rows'
    second=reader.view('advisor',audience:'product',limit:100,offset:100,page_changes:true)
    # A page of requests must not imply the original invoice or its selected terms disappeared.
    %w[billing terms lifecycle].each do |section|
      assert_equal first.fetch('sections').fetch(section).map { |row| row.fetch('id') },second.fetch('sections').fetch(section).map { |row| row.fetch('id') },section
    end
    assert_equal first.fetch('summary'),second.fetch('summary')
    refute_empty second.fetch('sections').fetch('changes')
    assert_equal 'changes',first.dig('page','mode')
    assert_equal 110,first.dig('page','total')
    assert_empty first.dig('sections','changes').map { |row| row['id'] } & second.dig('sections','changes').map { |row| row['id'] }
    legacy=reader.view('advisor',audience:'product',limit:1,offset:0)
    assert_equal 'all',legacy.dig('page','mode')
    assert_equal 1,legacy.fetch('sections').values.sum(&:size)
  end
end
