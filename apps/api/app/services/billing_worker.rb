# PostgreSQL-backed, at-least-once ActiveJob execution. No paid queue dependency.
class BillingWorker
  LEASE_SECONDS=120
  CLASSES=%w[BillingNormalizeJob BillingEvaluateJob].freeze
  def self.enqueue(job,at:Time.current,batch_id:nil)
    tenant,entity,case_id=job.arguments.first(3)
    raise Economics::Error.new('INVALID_JOB') unless CLASSES.include?(job.class.name) && %w[advisor ria].include?(case_id)
    BillingWorkItem.create!(tenant_id:tenant,entity_id:entity,case_id:case_id,job_id:job.job_id,job_class:job.class.name,job_data:job.serialize,status:'queued',run_at:at,batch_id:batch_id)
  end
  def self.perform_one(now:Time.current,after_execute:nil,job_id:nil)
    item=BillingWorkItem.transaction do
      ready=BillingWorkItem.where("(status='queued' AND run_at<=?) OR (status='running' AND leased_until<=?)",now,now)
      ready=ready.where(job_id:job_id) if job_id
      row=ready.order(:run_at,:id).lock('FOR UPDATE SKIP LOCKED').first
      if row
        row.update!(status:'running',attempts:row.attempts+1,lease_token:SecureRandom.uuid,leased_until:now+LEASE_SECONDS)
      end
      row
    end
    return nil unless item
    token=item.lease_token; platform=BillingPlatform.new(Workbench.new(role:'operator',tenant:item.tenant_id,entity:item.entity_id),item.case_id)
    begin
      raise Economics::Error.new('INVALID_JOB') unless CLASSES.include?(item.job_class) && item.job_data['job_class']==item.job_class && item.job_data['arguments'].first(3)==[item.tenant_id,item.entity_id,item.case_id]
      raise Economics::Error.new('RETRY_EXHAUSTED') if item.attempts>item.max_attempts
      result=ActiveJob::Base.execute(item.job_data.merge('provider_job_id'=>item.job_id))
      after_execute&.call(item,result) # Failure injection models crash after durable domain commit.
      status=result.is_a?(Hash) && %w[blocked quarantined].include?(result['status']) ? 'quarantined' : 'completed'
      finish(item,token,platform,status,result.is_a?(Hash) ? result : {},now,nil)
    rescue StandardError => error
      retrying=item.attempts<item.max_attempts
      finish(item,token,platform,retrying ? 'queued' : 'failed',{},now,error.is_a?(Economics::Error) ? error.code : error.class.name)
    end
    item.reload
  end
  def self.finish(item,token,platform,status,result,now,error)
    BillingWorkItem.transaction do
      item.lock!; return if item.lease_token!=token || item.status!='running'
      DemoScope.where(**platform.w.scope).lock.first!
      platform.store('work_attempt',{'job_id'=>item.job_id,'job_class'=>item.job_class,'attempt'=>item.attempts,'outcome'=>status,'error'=>error,'result'=>result},status:status=='completed' ? 'completed' : status=='quarantined' ? 'quarantined' : 'blocked')
      item.update!(status:status,result:result,last_error:error,run_at:status=='queued' ? now+[2**item.attempts,60].min : item.run_at,leased_until:nil,lease_token:nil)
    end
  end
  class Adapter
    def enqueue(job) = BillingWorker.enqueue(job)
    def enqueue_at(job,timestamp) = BillingWorker.enqueue(job,at:Time.at(timestamp).utc)
  end
end
