class BillingEvaluateJob < ActiveJob::Base
  def perform(tenant,entity,case_id,subject,a,b,purpose='billing')
    BillingPlatform.new(Workbench.new(role:'operator',tenant:tenant,entity:entity),case_id).command('EVALUATE',{'purpose'=>purpose,'subject_id'=>subject,'service_start'=>a,'service_end_exclusive'=>b},job_id)
  end
end
BillingEvaluateJob.queue_adapter=BillingWorker::Adapter.new
