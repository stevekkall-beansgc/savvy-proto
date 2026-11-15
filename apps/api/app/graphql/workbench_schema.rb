class WorkbenchSchema < GraphQL::Schema
  query DemoGraph::Query
  mutation DemoGraph::Mutation
  complexity_cost_calculation_mode :future
  max_depth 10
  max_complexity 150
  rescue_from(Economics::Error) { |err| raise GraphQL::ExecutionError.new(err.message, extensions: { code: err.code }) }
end
