# Run only on the guarded disposable synthetic test database.
ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class DisclosureLineageTest < Minitest::Test
  def setup
    SyntheticReset.call
    @w=Workbench.new(role:'operator'); @w.seed!
    DisclosureWorkbench.new(@w).bootstrap({},'disclosure-lineage-bootstrap')
    @m=@w.medallion
  end

  def test_ordinary_daily_fact_links_only_to_exact_consuming_runs_and_its_artifact
    source=@m.get!('advisor','disclosure_2027','fact','disclosure-adb-a-14')
    run=@m.get!('advisor','disclosure_2027','run','disclosure-option-run-average-daily-balance')
    %w[wrong-revision wrong-hash wrong-result unused].each do |variant|
      payload=Economics::Canonical.copy(run.payload)
      keys=%w[a_day_14 a_day_14_included]
      if variant=='wrong-result'
        payload['result']['details'].select { |detail| keys.include?(detail['id']) }.each do |detail|
          Array(detail['source_refs']).each { |ref| ref['hash']='0'*64 if ref['external_id']==source.external_id }
        end
      elsif variant=='unused'
        payload['result']['bindings'].reject! { |binding| keys.include?(binding['fact']) || (Array(binding['facts']) & keys).any? }
      else
        keys.each do |key|
          fact=payload['input_manifest']['facts'].fetch(key)
          ref=fact.fetch('evidence_refs').first
          ref['revision']+=1 if variant=='wrong-revision'
          ref['hash']='0'*64 if variant=='wrong-hash'
        end
      end
      @m.store!('advisor','disclosure_2027','run',id:"disclosure-lineage-#{variant}",status:'completed',payload:payload)
    end
    @m.store!('advisor','other_disclosure','run',id:'disclosure-lineage-other-namespace',status:'completed',payload:Economics::Canonical.copy(run.payload))
    @m.store!('ria','disclosure_2027','run',id:'disclosure-lineage-other-case',status:'completed',payload:Economics::Canonical.copy(run.payload))
    result=AudienceReadModel.new(@w).lineage_record('advisor',source.id.to_s,limit:100)
    edges=result.fetch('edges')
    assert edges.any? { |edge| edge.dig('input','external_id')=='disclosure-alternative-source' && edge.dig('output','id')==source.id.to_s }, 'Original artifact must link to the ordinary observation'
    execution=edges.select { |edge| edge['execution_status']=='recorded_execution' && edge.dig('input','id')==source.id.to_s }
    assert_includes execution.map { |edge| edge.dig('output','external_id') },run.external_id
    refute execution.any? { |edge| edge.dig('output','external_id').to_s.start_with?('disclosure-lineage-') },execution.inspect
    %w[wrong-revision wrong-hash wrong-result unused].each do |variant|
      other=@m.get!('advisor','disclosure_2027','run',"disclosure-lineage-#{variant}")
      reader=AudienceReadModel.new(@w)
      first=reader.lineage_record('advisor',other.id.to_s,limit:100)
      all=(0...first['edge_total']).step(100).flat_map { |offset| reader.lineage_record('advisor',other.id.to_s,limit:100,offset:offset)['edges'] }
      refute all.any? { |edge| edge['execution_status']=='recorded_execution' && edge.dig('input','id')==source.id.to_s },variant
    end
  end
end
