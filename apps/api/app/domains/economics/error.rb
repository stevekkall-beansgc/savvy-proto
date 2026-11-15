module Economics
  class Error < StandardError
    attr_reader :code, :path
    def initialize(code, message = code, path = [])
      @code, @path = code, path
      super(message)
    end
    def to_h = { code: code, message: message, path: path, evidenceIds: [] }
  end
end
