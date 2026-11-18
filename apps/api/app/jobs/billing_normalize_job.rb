class BillingNormalizeJob < ActiveJob::Base
  def perform(tenant,entity,case_id,delivery_id,source_id)
    service=BillingPlatform.new(Workbench.new(role:'operator',tenant:tenant,entity:entity),case_id)
    DemoScope.transaction do
      DemoScope.where(**service.w.scope).lock.first!
      BillingPipeline.new(service).normalize(delivery_id,source_id)
    end
  end
end
