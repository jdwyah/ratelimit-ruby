module RateLimit
  class NoopCache
    def fetch(name, opts, &method)
      yield
    end

    def write(name, value, opts=nil)
    end

    def read(name)
    end
  end
end
