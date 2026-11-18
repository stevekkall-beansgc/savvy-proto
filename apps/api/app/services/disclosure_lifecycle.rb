# Typed commercial and compensation calculations over independently retained
# fictional source observations. This graph never creates a cash or posting fact.
class DisclosureLifecycle
  def self.graph
    n=[]
    add=lambda { |id,op,unit,basis,extra={}| n << {'id'=>id,'op'=>op,'unit'=>unit,'basis'=>basis,'role'=>'intermediate'}.merge(extra) }
    %w[original_charge line_a line_b salary bonus loan forgiveness refund custody].each { |id| add.call(id,'fact','USD_minor','source_reported',{'key'=>id}) }
    add.call('unused_fraction','fact','scalar','scalar',{'key'=>'unused_fraction'})
    add.call('unused_exact','accrue','USD_minor','exact_accrual',{'left'=>'original_charge','right'=>'unused_fraction'})
    add.call('credit','assess','USD_minor','assessed',{'input'=>'unused_exact','rounding'=>'half_up','role'=>'terminal','output_class'=>'obligation','payer'=>'firm-demo','payee'=>'disclosure-alder-household','currency'=>'USD'})
    %w[a b].each { |id| add.call("credit_#{id}",'allocate_by','USD_minor','assessed',{'input'=>'credit','weights'=>{'a'=>'line_a','b'=>'line_b'},'recipient'=>id,'role'=>'terminal','output_class'=>'obligation','payer'=>'firm-demo','payee'=>'disclosure-alder-household','currency'=>'USD'}) }
    %w[salary bonus loan forgiveness refund custody original_charge].each do |id|
      add.call("assessed_#{id}",'assess','USD_minor','assessed',{'input'=>id,'rounding'=>'half_up'})
    end
    %w[salary bonus loan forgiveness].each do |id|
      add.call("#{id}_entitlement",'add','USD_minor','assessed',{'inputs'=>["assessed_#{id}"],'role'=>'terminal','output_class'=>'metric'})
    end
    add.call('service_retained','subtract','USD_minor','assessed',{'left'=>'assessed_original_charge','right'=>'credit','role'=>'terminal','output_class'=>'metric'})
    add.call('loan_outstanding','subtract','USD_minor','assessed',{'left'=>'assessed_loan','right'=>'assessed_forgiveness','role'=>'terminal','output_class'=>'metric'})
    add.call('refund_remaining','subtract','USD_minor','assessed',{'left'=>'credit','right'=>'assessed_refund','role'=>'terminal','output_class'=>'metric'})
    add.call('known_direct','add','USD_minor','assessed',{'inputs'=>%w[assessed_original_charge assessed_custody],'role'=>'terminal','output_class'=>'metric'})
    policy={'version'=>'disclosure-lifecycle-v1','nodes'=>n}; Economics::Engine.new.validate(policy:policy); policy
  end
end
