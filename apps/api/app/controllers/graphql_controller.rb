class GraphqlController < ActionController::API
  MAX_BYTES = 1_048_576
  def health
    render json: { status: "ok", synthetic: true, connected: false, contract_version: "0.6.0", engine_version: Economics::Engine::VERSION, source_revision: ENV.fetch("SAVVY_SOURCE_REVISION", "unknown"), immutable_preview: ENV["SAVVY_IMMUTABLE_PREVIEW"] == "1", eager_load: Rails.configuration.eager_load, reloading_enabled: Rails.configuration.enable_reloading }
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
    # Simulated local identities only. Not an authentication system.
    service = Workbench.new(role: request.headers.fetch("X-Demo-Role", "operator"))
    render json: WorkbenchSchema.execute(data["query"], variables: data["variables"] || {}, operation_name: data["operationName"], context: { workbench: service })
  rescue JSON::ParserError
    render json: { error: "INVALID_JSON" }, status: 400
  rescue Economics::Error => e
    render json: { errors: [{ message: e.message, extensions: { code: e.code } }] }, status: 403
  rescue StandardError => e
    Rails.logger.error("Synthetic GraphQL failure: #{e.class}")
    render json: { errors: [{ message: "The local service could not complete this request", extensions: { code: "INTERNAL_ERROR" } }] }, status: 500
  end
end
