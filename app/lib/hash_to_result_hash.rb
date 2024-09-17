module HashToResultHash
  refine Hash do
    def to_result_hash
      self # Simply returns the hash itself
    end
  end
end
