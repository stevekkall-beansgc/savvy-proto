# Shared fictional seed for explicit setup and visitor provisioning.
class DemoPresentationSeed
  def self.call(w = Workbench.new)
    raise 'Synthetic setup only' unless ENV['SYNTHETIC_DEMO'] == '1'
    w.seed!
    m = w.medallion
    unless m.source('advisor', 'baseline', 'policy').exists?
      m.bootstrap({}, 'presentation-medallion-bootstrap-v1')
    end
    %w[advisor ria].each do |case_id|
      unless m.source(case_id, 'baseline', 'run').exists?
        m.evaluate_case({'case_id'=>case_id, 'policy_id'=>"#{case_id}-policy-v1",
          'knowledge_cutoff'=>'2026-10-02T23:00:00Z'}, "presentation-#{case_id}-run-v1")
      end
      AudienceReadModel.new(w).refresh!(case_id) unless AudienceReadModel.new(w).projection(case_id)
    end
    unless m.source('advisor', DisclosureWorkbench::NS, 'publication').exists?
      DisclosureWorkbench.new(w).bootstrap({}, 'presentation-disclosure-bootstrap-v1')
    end
    unless m.source('ria', FinanceTiming::SCENARIO, 'run').exists?
      FinanceTiming.new(w).bootstrap({}, 'presentation-finance-bootstrap-v1')
    end
  end
end
