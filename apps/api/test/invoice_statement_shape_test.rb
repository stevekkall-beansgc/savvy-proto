ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class InvoiceStatementShapeTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new
    @operator.seed!
    @operator.medallion.bootstrap({},'invoice-shape-bootstrap')
  end

  def test_service_dates_and_signed_amounts_map_without_fabricated_unit_prices
    %w[advisor ria].each do |case_id|
      result=@operator.medallion.evaluate_case({'case_id'=>case_id,'policy_id'=>"#{case_id}-policy-v1",'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},"invoice-shape-#{case_id}")
      reader=AudienceReadModel.new(@operator)
      reader.refresh!(case_id)
      statement=reader.statement(case_id,limit:100)
      assert_equal result['id'],statement['run_id']
      assert_operator statement['total'],:>,1
      statement.fetch('lines').each_with_index do |line,index|
        item=line.fetch('invoice_line')
        assert_equal index+1,item['line_number']
        assert_equal line['label'],item['description']
        assert_equal line['minor'],item['amount_minor']
        assert_equal 'USD',item['currency']
        assert_equal '2026-09-01',item['service_period_start']
        assert_equal '2026-10-01',item['service_period_end_exclusive']
        assert_nil item['quantity'],'Do not pretend percentage fees have one unit'
        assert_nil item['unit_amount_minor'],'Do not copy an assessed amount into a rate'
        assert_equal result['id'],item['source_run_id']
      end
      assert_equal statement['total'],statement['lines'].map { |x| x.dig('invoice_line','id') }.uniq.length
      if case_id=='ria'
        credit=statement['lines'].find { |line| Integer(line['minor'])<0 }
        assert credit
        assert_operator Integer(credit.dig('invoice_line','amount_minor')),:<,0
      end
    end
  end
end
