module RateLimit

  class NoopStats
    # receives increment("it.ratelim.limitcheck", {:tags=>["policy_group:page_view", "pass:true"]})
    def increment(name, opts)
    end
  end
end
