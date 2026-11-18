# Compatibility adapter for the historical commercial policy envelope.
# Rate selection and monetary operations are delegated to the shared interpreter.
class CommercialEngine < Economics::Engine
  def validate_policy!(policy)
    scope!(policy, policy)
    raise Economics::Error.new('SYNTHETIC_ONLY') unless policy['synthetic'] == true
    true
  end

end
