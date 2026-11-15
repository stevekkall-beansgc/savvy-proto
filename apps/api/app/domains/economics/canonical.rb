require "json"
require "digest"
module Economics
  module Canonical
    module_function
    def sort(value)
      case value
      when Hash then value.keys.sort.to_h { |k| [k, sort(value[k])] }
      when Array then value.map { |item| sort(item) }
      else value
      end
    end
    def hash(value) = Digest::SHA256.hexdigest(JSON.generate(sort(value)))
    def copy(value) = JSON.parse(JSON.generate(value))
  end
end
