require 'json'
require 'base64'
require 'bigdecimal'

# Source mapping, identity, normalization and completeness. No fee calculation.
class BillingPipeline
  TYPES=%w[account balance time event cash cost accounting measure].freeze
  FIELDS=%w[id revision type observed_at billing_subject_id customer_id account_id active_from active_to eligible dimensions label date amount_minor currency quantity direction reason status document_id payer_id payee_id withdrawn provider reported_status recognized_minor deferred_minor journal_id unit basis value collection attributes billing_subject_label].freeze
  def initialize(platform) = @p=platform
  def original_bytes(delivery) = @p.get('artifact',delivery.payload.fetch('artifact_id')).original_bytes
  def register(input)
    @p.w.guard!('operator'); name=@p.id!(input.fetch('name')); config=input.fetch('mapping')
    @p.error('VALIDATION_ERROR') unless config.is_a?(Hash) && config['fields'].is_a?(Hash) && config['fields'].size.between?(1,40) && %w[json ndjson].include?(config['format'])
    @p.error('VALIDATION_ERROR') unless (config.keys-%w[format records_path fields coercions constants]).empty? && (config['fields'].keys-FIELDS).empty?
    @p.error('VALIDATION_ERROR') unless config['fields'].values.all? { |path| path.is_a?(String) && path.match?(/\A[a-zA-Z0-9_.]{1,100}\z/) }
    conversions=config.fetch('coercions',{}); defaults=config.fetch('constants',{})
    @p.error('VALIDATION_ERROR') unless conversions.is_a?(Hash) && defaults.is_a?(Hash) && ((conversions.keys+defaults.keys)-FIELDS).empty? && conversions.values.all? { |v| %w[integer decimal_usd rational_decimal boolean us_date epoch_seconds identifier string].include?(v) } && defaults.values.all? { |v| [String,Integer,TrueClass,FalseClass,NilClass].any? { |type| v.is_a?(type) } }
    row=@p.store('source',{'name'=>name,'mapping'=>config,'version'=>@p.rows('source').where("payload->>'name' = ?",name).count+1},status:'active')
    {'source_id'=>row.external_id,'mapping_hash'=>row.payload_hash}
  end
  def ingest(input)
    @p.w.guard!('operator'); source=@p.get('source',input.fetch('source_id')); identity=@p.id!(input.fetch('delivery_key'))
    @p.error('VALIDATION_ERROR','Supply raw text or raw_base64, not both') if input.key?('raw') && input.key?('raw_base64')
    raw=input.key?('raw_base64') ? Base64.strict_decode64(input.fetch('raw_base64')) : input.fetch('raw')
    @p.error('RESOURCE_LIMIT') unless raw.is_a?(String) && raw.bytesize.between?(0,750_000)
    previous=@p.rows('delivery').find_by(external_id:identity)
    if previous
      unless original_bytes(previous)==raw && previous.payload['source_id']==source.external_id
        artifact=@p.store('artifact',{'source_id'=>source.external_id,'sha256'=>Digest::SHA256.hexdigest(raw),'conflicts_with'=>previous.external_id},status:'retained',parent:source,bytes:raw)
        arrival=@p.store('delivery',{'source_id'=>source.external_id,'source_name'=>source.payload['name'],'artifact_id'=>artifact.external_id,'conflicts_with'=>previous.external_id,'source_delivery_key'=>identity},status:'retained',parent:artifact)
        execution=@p.store('normalization',{'service'=>'BillingNormalizeJob','delivery_id'=>arrival.external_id,'source_id'=>source.external_id,'records'=>[],'errors'=>[{'code'=>'SOURCE_CONFLICT','message'=>'Delivery identity already has different bytes or mapping'}]},status:'quarantined',parent:arrival)
        return {'delivery_id'=>arrival.external_id,'execution_id'=>execution.external_id,'status'=>'quarantined','errors'=>execution.payload['errors']}
      end
      return {'delivery_id'=>previous.external_id,'status'=>latest_execution(previous)&.status || 'retained','duplicate'=>true}
    end
    artifact=@p.store('artifact',{'source_id'=>source.external_id,'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>source.payload.dig('mapping','format')},status:'retained',parent:source,bytes:raw)
    delivery=@p.store('delivery',{'source_id'=>source.external_id,'source_name'=>source.payload['name'],'artifact_id'=>artifact.external_id,'mapping_hash'=>source.payload_hash,'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>source.payload.dig('mapping','format')},id:identity,status:'retained',parent:artifact)
    outcome=BillingNormalizeJob.perform_now(@p.w.tenant,@p.w.entity,@p.case_id,delivery.external_id,source.external_id)
    {'delivery_id'=>delivery.external_id,**outcome}
  end
  def latest_execution(delivery) = @p.rows('normalization').where(parent_id:delivery.id).order(:id).last
  def path(row,name)
    name.to_s.split('.').reduce(row) { |value,key| value.is_a?(Hash) ? value[key] : nil }
  end
  def record_key(source,record)
    "bp-record-#{Digest::SHA256.hexdigest([source.payload['name'],record['type'],record['id']].join(':'))[0,40]}"
  end
  def coerce(value,type)
    return nil if value.nil?
    text=value.is_a?(BigDecimal) ? value.to_s('F') : value.to_s
    case type
    when 'integer'
      @p.error('INVALID_SOURCE','Expected an integer source value') unless text.match?(/\A-?\d{1,16}\z/); Integer(text,10)
    when 'decimal_usd','rational_decimal'
      @p.error('INVALID_SOURCE','Expected an exact decimal string') unless text.match?(/\A-?\d{1,16}(?:\.\d{1,12})?\z/)
      value=Rational(text)*(type=='decimal_usd' ? 100 : 1)
      type=='rational_decimal' || value.denominator!=1 ? "#{value.numerator}/#{value.denominator}" : value.numerator
    when 'boolean'
      @p.error('INVALID_SOURCE','Expected true or false') unless %w[true false].include?(text); text=='true'
    when 'us_date'
      @p.error('INVALID_SOURCE') unless text.match?(/\A\d{2}\/\d{2}\/\d{4}\z/); Date.strptime(text,'%m/%d/%Y').iso8601
    when 'epoch_seconds'
      @p.error('INVALID_SOURCE') unless text.match?(/\A\d{1,12}\z/); Time.at(Integer(text,10)).utc.iso8601(6)
    when 'identifier' then "source-#{Digest::SHA256.hexdigest(text)[0,40]}"
    when 'string' then text
    else @p.error('INVALID_SOURCE','Unsupported source conversion') end
  rescue ArgumentError,TypeError
    @p.error('INVALID_SOURCE','Source value does not match its configured representation')
  end
  def normalize(delivery_id,source_id)
    delivery=@p.get('delivery',delivery_id); source=@p.get('source',source_id)
    @p.error('SCOPE_MISMATCH','Replay must use a version of the original source mapping') unless delivery.payload['source_name']==source.payload['name']
    mapping=source.payload.fetch('mapping'); errors=[]; normalized=[]
    begin
      raw=original_bytes(delivery)
      active=@p.rows('source').where("payload->>'name' = ?",source.payload['name']).order(:id).last
      @p.error('MAPPING_SUPERSEDED','Replay with the current source mapping version') unless active.external_id==source.external_id
      data=mapping['format']=='ndjson' ? raw.lines.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line,decimal_class:BigDecimal) } : JSON.parse(raw,decimal_class:BigDecimal)
      data=path(data,mapping['records_path']) if mapping['records_path'].present?
      @p.error('INVALID_SOURCE','Expected a bounded array of records') unless data.is_a?(Array) && data.size.between?(1,5000)
      records=data.each_with_index.map do |raw,index|
        @p.error('INVALID_SOURCE','Each source row must be an object') unless raw.is_a?(Hash)
        row=mapping.fetch('constants',{}).merge(mapping['fields'].to_h { |key,name| [key,path(raw,name)] }.compact)
        mapping.fetch('coercions',{}).each { |field,conversion| row[field]=coerce(row[field],conversion) }
        canonical!(row).merge('source_name'=>source.payload['name'])
      rescue Economics::Error => e
        errors << {'row'=>index+1,'code'=>e.code,'message'=>e.message}; nil
      end
      ids=records.compact.map { |r| [r['id'],r['revision']] }
      @p.error('DUPLICATE_SOURCE','Duplicate source identity/revision in one delivery') unless ids.uniq.size==ids.size
      # A delivery is atomic: retain raw bytes and quarantine, without accepting a subset.
      if errors.empty?
        records.each do |record|
          key=record_key(source,record)
          candidates=@p.rows('normalized').where(external_id:key).where("(payload->>'source_revision')::integer = ?",record['revision']).order(:id).to_a
          prior=candidates.last
          if prior && prior.payload['record']!=record
            original_sha=prior.payload['raw_sha256'] || Digest::SHA256.hexdigest(original_bytes(@p.get('delivery',prior.payload['delivery_id'])))
            reprocessing=original_sha==Digest::SHA256.hexdigest(raw) && source.payload['version']>prior.payload.fetch('mapping_version',1)
            errors << {'record_id'=>record['id'],'code'=>'SOURCE_CONFLICT','message'=>'The same source identity/revision has different original evidence'} unless reprocessing
          end
        end
      end
      if errors.empty?
        records.each do |record|
          key=record_key(source,record)
          existing=@p.rows('normalized').where(external_id:key).where("(payload->>'source_revision')::integer = ?",record['revision']).order(:id).last
          existing=nil if existing && existing.payload['mapping_id']!=source.external_id
          row=existing || @p.store('normalized',{'record'=>record,'source_revision'=>record['revision'],'mapping_id'=>source.external_id,'mapping_version'=>source.payload['version'],'mapping_hash'=>source.payload_hash,'raw_sha256'=>Digest::SHA256.hexdigest(raw),'delivery_id'=>delivery.external_id,'source_observed_at'=>record['observed_at'],'received_at'=>delivery.recorded_at.iso8601(6)},id:key,revision:(@p.rows('normalized').where(external_id:key).maximum(:revision)||0)+1,status:'accepted',parent:delivery,subject_id:record['billing_subject_id'],product_id:record['type'])
          normalized << {'record_id'=>row.external_id,'database_record_id'=>row.id.to_s,'revision'=>row.revision,'hash'=>row.payload_hash}
        end
      end
    rescue JSON::ParserError
      errors << {'code'=>'INVALID_JSON','message'=>'Original bytes could not be parsed as the configured format'}
    rescue Economics::Error => e
      errors << {'code'=>e.code,'message'=>e.message}
    end
    result=@p.store('normalization',{'service'=>'BillingNormalizeJob','adapter'=>'inline','delivery_id'=>delivery.external_id,'source_id'=>source.external_id,'mapping_hash'=>source.payload_hash,'records'=>normalized,'errors'=>errors},status:errors.empty? ? 'completed' : 'quarantined',parent:delivery)
    {'execution_id'=>result.external_id,'status'=>result.status,'record_count'=>normalized.size,'errors'=>errors}
  end
  def canonical!(row)
    row=row.compact; type=row['type']; @p.error('INVALID_SOURCE','Unknown record type') unless TYPES.include?(type)
    %w[id].each { |key| @p.id!(row.fetch(key)) }
    @p.error('INVALID_SOURCE','A positive source revision is required') unless row['revision'].is_a?(Integer) && row['revision'].between?(1,1_000_000)
    @p.clock(row.fetch('observed_at'))
    @p.error('FUTURE_EVIDENCE','Source observation time is in the future') if @p.clock(row['observed_at'])>Time.current
    %w[billing_subject_id customer_id account_id].each { |key| @p.id!(row.fetch(key)) }
    @p.error('INVALID_SOURCE') if row.key?('withdrawn') && ![true,false].include?(row['withdrawn'])
    return row if row['withdrawn']==true
    case type
    when 'account'
      @p.date!(row.fetch('active_from')); finish=row['active_to']; @p.date!(finish) unless finish.nil?
      @p.error('INVALID_INTERVAL') if finish && @p.date!(row['active_from'])>=@p.date!(finish)
      @p.error('INVALID_SOURCE','Eligibility must be a Boolean') unless [true,false].include?(row['eligible'])
      @p.error('INVALID_SOURCE') unless row.fetch('dimensions',{}).is_a?(Hash) && row.fetch('dimensions',{}).size<=20
      row['label']=row['label'].to_s.presence || row['customer_id']; @p.error('RESOURCE_LIMIT') if row['label'].length>120
    else
      @p.date!(row.fetch('date')); @p.error('UNIT_MISMATCH') unless type=='time' || row['currency']=='USD'
      actual=%w[balance time measure].include?(type) || (type=='cash' && row['status']=='confirmed') || (type=='accounting' && row['reported_status']=='posted')
      @p.error('FUTURE_EVIDENCE','An actual observation cannot predate its economic day') if actual && @p.date!(row['date'])>@p.clock(row['observed_at']).to_date
      if type=='time'
        @p.error('INVALID_NUMBER') unless row['quantity'].is_a?(String) && row['quantity'].match?(/\A\d+(?:\/[1-9]\d*)?\z/) && row['quantity'].length<=40 && Rational(row['quantity'])<=100_000
      elsif type=='measure'
        @p.error('INVALID_SOURCE','Generic measures require typed source values') unless (row['unit']=='USD_minor' && row['basis']=='source_reported') || (row['unit']=='scalar' && row['basis']=='scalar')
        value=row.fetch('value'); @p.error('INVALID_NUMBER') unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+(?:\/[1-9]\d*)?\z/) && value.length<=40)
        @p.error('INVALID_NUMBER') if Rational(value).abs>10**15
        @p.id!(row.fetch('collection')); @p.error('INVALID_SOURCE','Collection name is reserved') if %w[events balances hours approved_events payment_applications].include?(row['collection'])
        attributes=row.fetch('attributes',{}); reserved=%w[id revision tenant_id entity_id approved currency recorded_at unit basis value collection date economic_date evidence_refs]
        @p.error('INVALID_SOURCE') unless attributes.is_a?(Hash) && attributes.size<=20 && (attributes.keys&reserved).empty?
      elsif type=='balance'
        value=row.fetch('amount_minor')
        @p.error('INVALID_NUMBER') unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+(?:\/[1-9]\d*)?\z/) && value.length<=40)
        @p.error('INVALID_NUMBER') unless Rational(value).between?(0,10**15)
      elsif type=='cost' && row['status']=='unknown'
        @p.m.reason!(row.fetch('reason'))
        @p.error('INVALID_SOURCE','Unknown cost must not supply an amount') if row['amount_minor']
      else
        Economics::Engine.integer!(row.fetch('amount_minor'),'source amount',max:10**15)
      end
      if type=='event'
        @p.error('INVALID_SOURCE') unless %w[charge credit payout].include?(row['direction'])
        @p.m.reason!(row.fetch('reason'))
      end
      if type=='cash'
        @p.id!(row.fetch('document_id')); @p.error('INVALID_SOURCE') unless %w[inbound outbound].include?(row['direction']) && %w[confirmed pending].include?(row['status'])
        %w[payer_id payee_id].each { |key| @p.id!(row.fetch(key)) }
      end
      if type=='accounting'
        @p.id!(row.fetch('document_id'))
        @p.error('INVALID_SOURCE') unless row['provider']=='mock_campfire' && %w[received posted rejected].include?(row['reported_status'])
        %w[recognized_minor deferred_minor].each { |key| Economics::Engine.integer!(row[key],key) unless row[key].nil? }
        @p.id!(row.fetch('journal_id')) if row['reported_status']=='posted'
      end
    end
    row
  rescue KeyError,ArgumentError,TypeError
    @p.error('INVALID_SOURCE','A required source field is missing or malformed')
  end
  def current(cutoff=Time.current.iso8601(6),types:nil)
    relation=@p.rows('normalized').where('recorded_at <= ?',@p.clock(cutoff))
    relation=relation.where(product_id:types) if types
    latest=relation
      .select("DISTINCT ON (external_id) medallion_evidence.*")
      .order(Arel.sql("external_id, (payload->>'source_revision')::integer DESC, COALESCE((payload->>'mapping_version')::integer,1) DESC, id DESC")).to_sql
    mappings=@p.rows('source').where('recorded_at <= ?',@p.clock(cutoff)).select("DISTINCT ON (payload->>'name') external_id").order(Arel.sql("payload->>'name', id DESC")).to_sql
    MedallionEvidence.from("(#{latest}) medallion_evidence").where("COALESCE(payload->'record'->>'withdrawn','false') <> 'true'").where("payload->>'mapping_id' IN (#{mappings})")
  end
  def accounts(subject=nil,cutoff=Time.current.iso8601(6))
    relation=current(cutoff,types:['account']).where(status:'accepted')
    relation=relation.where(subject_id:subject) if subject
    relation
  end
  def manifest(subject,a,b,cutoff,requirements:{'balances'=>'daily'})
    account_rows=accounts(subject,cutoff).where("payload->'record'->>'active_from' < ? AND (payload->'record'->>'active_to' IS NULL OR payload->'record'->>'active_to' > ?)",b.iso8601,a.iso8601).limit(101).to_a
    @p.error('RESOURCE_LIMIT','A single billing group supports at most 100 accounts; page the book by group') if account_rows.size>100
    @p.error('INCOMPLETE_SOURCE','No dated accounts are available for this billing subject') if account_rows.empty?
    roster=account_rows.select { |row| r=row.payload['record']; @p.date!(r['active_from'])<b && (!r['active_to'] || a<@p.date!(r['active_to'])) }
    @p.error('INCOMPLETE_SOURCE','No active accounts in this service interval') if roster.empty?
    accounts=roster.map { |row| row.payload['record'] }; ids=accounts.map { |r| r['account_id'] }
    @p.error('RULE_CONFLICT','More than one account membership claims an account') unless ids.uniq.size==ids.size
    mode=requirements.fetch('balances'); @p.error('INVALID_SOURCE') unless %w[daily ending none].include?(mode)
    records=current(cutoff,types:%w[balance time event measure]).where(subject_id:subject,status:'accepted')
      .where("payload->'record'->>'date' >= ? AND payload->'record'->>'date' < ?",a.iso8601,b.iso8601).limit(5001).to_a
    @p.error('RESOURCE_LIMIT') if records.size>5000
    records.select! { |row| r=row.payload['record']; (ids.include?(r['account_id']) || (r['type']=='measure' && r['account_id']==subject)) && a<=@p.date!(r['date']) && @p.date!(r['date'])<b }
    balances=records.select { |row| row.product_id=='balance' }
    balances.select! { |row| row.payload.dig('record','date')==(b-1).iso8601 } if mode=='ending'
    balances=[] if mode=='none'
    records.reject! { |row| row.product_id=='balance' && !balances.include?(row) }
    index=balances.group_by { |row| r=row.payload['record']; [r['account_id'],r['date']] }
    expected=accounts.flat_map do |account|
      days=mode=='daily' ? (a...b).to_a : mode=='ending' ? [b-1] : []
      days.filter_map do |day|
        next if day<@p.date!(account['active_from']) || (account['active_to'] && day>=@p.date!(account['active_to']))
        matches=index[[account['account_id'],day.iso8601]] || []
        @p.error(matches.empty? ? 'INCOMPLETE_SOURCE' : 'RULE_CONFLICT',"Expected exactly one balance for #{account['account_id']} on #{day}") unless matches.one?
        [account,day,matches.first]
      end
    end
    @p.error('RESOURCE_LIMIT','Engine manifest exceeds its per-group safety limit') if expected.size+records.size>850
    refs=roster+records
    base={'tenant_id'=>@p.w.tenant,'entity_id'=>@p.w.entity,'approved'=>true,'currency'=>'USD'}
    facts={}
    expected.each do |account,day,row|
      key="balance_#{Digest::SHA256.hexdigest(row.external_id)[0,24]}"
      facts[key]=base.merge('id'=>row.external_id,'revision'=>row.revision,'recorded_at'=>row.recorded_at.iso8601(6),'unit'=>'USD_minor','basis'=>'source_reported','value'=>row.payload['record']['amount_minor'].to_s,'collection'=>'balances','account_id'=>account['account_id'],'eligible'=>account['eligible'],'economic_date'=>day.iso8601,'date'=>day.iso8601,'dimensions'=>account.fetch('dimensions',{}),'evidence_refs'=>[row.parent_id.to_s])
    end
    records.reject { |row| row.product_id=='balance' }.each do |row|
      r=row.payload['record']; next if %w[cash cost].include?(r['type'])
      if r['type']=='measure'
        facts["measure_#{row.id}"]=base.merge(r.fetch('attributes',{})).merge('id'=>row.external_id,'revision'=>row.revision,'recorded_at'=>row.recorded_at.iso8601(6),'unit'=>r['unit'],'basis'=>r['basis'],'value'=>r['value'].to_s,'collection'=>r['collection'],'account_id'=>r['account_id'],'economic_date'=>r['date'],'evidence_refs'=>[row.parent_id.to_s])
        next
      end
      if r['type']=='event'
        decision=@p.rows('event_review').where(parent_id:row.id).where('recorded_at <= ?',@p.clock(cutoff)).order(:id).last
        next unless decision && decision.status=='approved' && decision.payload['record_hash']==row.payload_hash
      end
      facts["record_#{row.id}"]=base.merge('id'=>row.external_id,'revision'=>row.revision,'recorded_at'=>row.recorded_at.iso8601(6),'unit'=>r['type']=='time' ? 'scalar' : 'USD_minor','basis'=>r['type']=='time' ? 'scalar' : 'assessed','value'=>r['type']=='time' ? r['quantity'] : r['amount_minor'].to_s,'collection'=>r['type']=='time' ? 'hours' : 'events','direction'=>r['direction'],'account_id'=>r['account_id'],'economic_date'=>r['date'],'evidence_refs'=>[row.parent_id.to_s])
    end
    {'subject_id'=>subject,'requirements'=>requirements,'accounts'=>accounts.sort_by { |r| r['account_id'] },'records'=>refs.map { |r| {'id'=>r.external_id,'revision'=>r.revision,'hash'=>r.payload_hash,'kind'=>r.product_id,'record_id'=>r.id.to_s} }.sort_by { |r| r['id'] },'engine'=>{'facts'=>facts}}
  end
end
