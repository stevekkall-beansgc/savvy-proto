ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

# Independent adversarial checks on the retained invoice and its proposed replacement.
class DisclosureCorrectionIndependentStressTest < Minitest::Test
  def setup
    SyntheticReset.call
    @workbench=Workbench.new(role:'operator'); @workbench.seed!
    @service=DisclosureWorkbench.new(@workbench)
    @service.bootstrap({},'independent-correction-bootstrap')
    @policy=@service.get('policy','disclosure-policy-v1')
    @original=@service.get('run','disclosure-run-v1')
    @baseline=Economics::Canonical.copy(@original.payload.fetch('result'))
  end

  def modified
    Economics::Canonical.copy(@baseline)
  end
  def item(result,id)
    result.fetch('details').find { |detail| detail['id']==id }
  end
  def unsafe_unchanged?(result, policy=@policy)
    !@service.correction_required?(result,policy,@original)
  rescue Economics::Error
    false # Rejecting incomplete evidence is also safe.
  end

  def test_same_total_reallocations_are_never_unchanged
    [1, 99, 1000, 20000, 39999].each do |delta|
      result=modified
      item(result,'line_a')['assessed_minor'] += delta
      item(result,'line_b')['assessed_minor'] -= delta
      refute unsafe_unchanged?(result), "same-total movement #{delta} was ignored"
    end
  end

  def test_missing_or_changed_economic_identity_is_never_unchanged
    %w[charge line_a line_b].each do |id|
      [['payer',nil], ['payee',nil], ['currency',nil], ['payer','unrelated-party'],
       ['payee','unrelated-party'], ['currency','EUR'], ['interval',nil],
       ['unit','EUR_minor'], ['basis','source_reported'], ['output_class','metric']].each do |key,value|
        result=modified
        item(result,id)[key]=value
        refute unsafe_unchanged?(result), "#{id}.#{key}=#{value.inspect} was ignored"
      end
    end
  end

  def test_duplicate_missing_and_unbalanced_outputs_fail_closed
    %w[charge line_a line_b].each do |id|
      missing=modified; missing['details'].reject! { |detail| detail['id']==id }
      refute unsafe_unchanged?(missing), "missing #{id} was ignored"
      duplicate=modified; duplicate['details'] << item(duplicate,id).dup
      refute unsafe_unchanged?(duplicate), "duplicate #{id} was ignored"
    end
    result=modified; item(result,'line_a')['assessed_minor'] += 1
    assert_equal 'INCOMPLETE_SOURCE', assert_raises(Economics::Error) { @service.correction_required?(result,@policy,@original) }.code
  end

  def test_nonallocated_equal_charge_requires_correction
    %w[hourly fixed net-worth optional-service].each do |name|
      policy=@service.get('policy',"disclosure-option-#{name}")
      run=@service.get('run',"disclosure-option-run-#{name}")
      result=Economics::Canonical.copy(run.payload.fetch('result'))
      item(result,'charge')['assessed_minor']=100000
      assert_equal true, @service.correction_required?(result,policy,@original), "#{name} should require correction"
    end
  end
end
