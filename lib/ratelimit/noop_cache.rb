module RateLimit
  class NoopCache
    def fetch(name, opts, &method)
      yield
    end
  end
end
