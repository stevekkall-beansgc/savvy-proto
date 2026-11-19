class GraphqlController < ActionController::API
  MAX_BYTES = 1_048_576

  def demo_session
    return head :not_found unless ENV['SYNTHETIC_DEMO'] == '1' && request.headers['X-Savvy-Public-Demo'] == '1'
    session = DemoSession.new(request.headers['X-Savvy-Demo-Token'])
    if request.delete?
      session.close
      head :no_content
    else
      render json: { token: session.start }, status: :created
    end
  rescue Economics::Error => e
    render json: { error: e.message }, status: :too_many_requests
  end
  def health
    render json: { status: "ok", synthetic: true, connected: false, contract_version: "0.8.0", engine_version: Economics::Engine::VERSION, source_revision: ENV.fetch("SAVVY_SOURCE_REVISION", "unknown"), immutable_preview: ENV["SAVVY_IMMUTABLE_PREVIEW"] == "1", eager_load: Rails.configuration.eager_load, reloading_enabled: Rails.configuration.enable_reloading }
  end
  def execute
    raise Economics::Error.new("SYNTHETIC_ONLY") unless ENV["SYNTHETIC_DEMO"] == "1"
    return render(json: { error: "BODY_TOO_LARGE" }, status: 413) if request.raw_post.bytesize > MAX_BYTES
    origin = request.headers["Origin"]
    if origin.present? && !%w[http://localhost:3100 http://127.0.0.1:3100 http://localhost:3101 http://127.0.0.1:3101 http://localhost:3102 http://127.0.0.1:3102 http://localhost:3103 http://127.0.0.1:3103].include?(origin)
      return render(json: { error: "LOCAL_ORIGIN_REQUIRED" }, status: 403)
    end
    return render(json: { error: "JSON_CONTENT_TYPE_REQUIRED" }, status: 415) unless request.media_type == "application/json"
    data = JSON.parse(request.raw_post)
    unless data.is_a?(Hash) && data["query"].is_a?(String) && data["query"].bytesize <= 50000 && (data["variables"].nil? || data["variables"].is_a?(Hash))
      return render(json: { error: "INVALID_GRAPHQL_ENVELOPE" }, status: 400)
    end
    role = request.headers.fetch('X-Demo-Role', 'operator')
    if request.headers['X-Savvy-Public-Demo'] == '1'
      return execute_public(data, role)
    end
    render json: execute_query(data['query'], data, Workbench.new(role: role))
  rescue JSON::ParserError
    render json: { error: "INVALID_JSON" }, status: 400
  rescue Economics::Error => e
    render json: { errors: [{ message: e.message, extensions: { code: e.code } }] }, status: 403
  rescue StandardError => e
    Rails.logger.error("Synthetic GraphQL failure: #{e.class}")
    render json: { errors: [{ message: "The local service could not complete this request", extensions: { code: "INTERNAL_ERROR" } }] }, status: 500
  end

  private

  def execute_query(query, data, workbench)
    options = { variables: data['variables'] || {}, operation_name: data['operationName'], context: { workbench: workbench } }
    query.is_a?(String) ? WorkbenchSchema.execute(query, **options) : WorkbenchSchema.execute(document: query, **options)
  end

  def execute_public(data, role)
    # Parse with the same GraphQL parser used for execution. Only the selected
    # operation matters, and ambiguous documents are rejected by the schema.
    document = GraphQL.parse(data['query'])
    operations = document.definitions.grep(GraphQL::Language::Nodes::OperationDefinition)
    selected = data['operationName'] ? operations.find { |op| op.name == data['operationName'] } : operations.first
    session = DemoSession.new(request.headers['X-Savvy-Demo-Token'])
    mutating = selected&.operation_type == 'mutation'
    workspace = session.workspace(role: role, require_active: mutating)
    if mutating
      # Workbench checks again under its write lock, so reset and a command
      # cannot race and the command keeps its own transaction boundary.
      session.require_active!(workspace)
    elsif !session.active?(workspace)
      workspace = Workbench.new(role: role)
    end
    render json: execute_query(document, data, workspace)
  rescue GraphQL::ParseError
    render json: { errors: [{ message: 'Invalid GraphQL document.' }] }, status: :bad_request
  end
end
