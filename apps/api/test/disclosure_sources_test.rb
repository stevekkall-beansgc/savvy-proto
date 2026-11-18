ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require 'minitest/autorun'

class DisclosureSourcesTest < Minitest::Test
  def observation(id, date, member, revision=1, recorded='2027-02-02T00:00:00Z')
    {'id'=>id,'revision'=>revision,'recorded_at'=>recorded,'tenant_id'=>'tenant','entity_id'=>'entity','currency'=>'USD',
      'date'=>date,'member_id'=>member,'holding_id'=>id,'amount_minor'=>100,'eligible'=>true}
  end
  def select(rows, dates=['2027-02-01'], cutoff='2027-02-03T00:00:00Z')
    DisclosureSources.select(observations:rows,members:%w[a b],holdings:{'a'=>['a'],'b'=>['b']},dates:dates,cutoff:cutoff,tenant_id:'tenant',entity_id:'entity')
  end
  def test_coverage_revision_and_knowledge_cutoff
    rows=[observation('a','2027-02-01','a'),observation('b','2027-02-01','b'),observation('a','2027-02-01','a',2,'2027-02-04T00:00:00Z').merge('amount_minor'=>200)]
    assert_equal 100,select(rows).find { |r| r['id']=='a' }['amount_minor']
    assert_equal 200,select(rows,['2027-02-01'],'2027-02-05T00:00:00Z').find { |r| r['id']=='a' }['amount_minor']
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { select(rows,['2027-02-01','2027-02-02']) }.code
  end
  def test_correction_to_date_vacates_old_day
    rows=[observation('a','2027-02-01','a'),observation('b','2027-02-01','b'),observation('a','2027-02-02','a',2)]
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { select(rows) }.code
    rows[-1]['member_id']='b'
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { select(rows) }.code
  end
  def test_conflicts_and_scope_are_rejected
    a=observation('a','2027-02-01','a'); b=observation('b','2027-02-01','b')
    assert_equal 'DUPLICATE_SOURCE',assert_raises(Economics::Error) { select([a,a,b]) }.code
    assert_equal 'SOURCE_CONFLICT',assert_raises(Economics::Error) { select([a,b,a.merge('id'=>'other')]) }.code
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { select([a,b.merge('entity_id'=>'other')]) }.code
  end
  def test_membership_coverage_and_overlap
    rows=%w[a b].map { |id| {'id'=>id,'membership_id'=>"membership-#{id}",'revision'=>1,'group_id'=>'household','effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','recorded_at'=>'2027-01-31T00:00:00Z'} }
    options={memberships:rows,service_start:'2027-02-01',service_end_exclusive:'2027-03-01',cutoff:'2027-02-01T00:00:00Z',group_id:'household'}
    assert_equal 2,DisclosureSources.memberships!(**options).size
    assert_equal 'RULE_CONFLICT',assert_raises(Economics::Error) { DisclosureSources.memberships!(**options.merge(memberships:rows+[rows.first.merge('membership_id'=>'other')])) }.code
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { DisclosureSources.memberships!(**options.merge(memberships:[rows.first.merge('effective_to'=>'2027-02-15')])) }.code
  end

end
