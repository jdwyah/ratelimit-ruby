# Don't use me in prod
# Just a toy for testing
module RateLimit
  class ToyCache
    @@cache = {}

    def fetch(name, opts, &block)
      result = read(name)

      return result unless result.nil?

      r = yield

      write(name, r)
      read(name)
    end

    def write(name, value, opts=nil)
      @@cache[name] = value
    end

    def read(name)
      @@cache[name]
    end
  end
end
