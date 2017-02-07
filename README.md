# ratelimit-ruby

Rate Limit your Ruby app using http://www.ratelim.it

```ruby
limiter =  RateLimit::Limiter.new(apikey: "ACCT_ID|APIKEY")

# only need to do this on startup
# limit to 1 per hour
limiter.upsert_limit("pageload", 1, RateLimIt::HOURLY_ROLLING)

if limiter.pass?("pageload")
  do_hourly_thing()
end
```
See full documentation http://www.ratelim.it/documentation


## Supports

* [RateLimits](http://www.ratelim.it/documentation/basic_rate_limits)
* Millions of individual limits sharing the same policies
* WebUI for tweaking limits & feature flags
* Logging to help you debug
* [Concurrency](http://www.ratelim.it/documentation/concurrency) & Semaphores
* Infinite retention for [deduplication workflows](http://www.ratelim.it/documentation/once_and_only_once)
* [FeatureFlags](http://www.ratelim.it/documentation/feature_flags) as a Service

## Options and Defaults
```ruby
limiter =  RateLimit::Limiter.new(
  apikey: "ACCT_ID|APIKEY",
  on_error: :log_and_pass, # :log_and_pass, :log_and_hit, :throw
  logger: nil, # pass in your own logger here. ie Rails.logger
  debug: false,  #Faraday debugging
  stats: nil, # receives increment("it.ratelim.limitcheck", {:tags=>["policy_group:page_view", "pass:true"]})
  shared_cache: nil, # Something that quacks like Rails.cache ideally memcached
                     # used to avoid hitting feature flag endpoint too much
  in_process_cache: nil # Something like ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)
                        # used to memoize featureflags if used in tight loops
)
```

## Full Example with Feature Flags
```ruby
@limiter = RateLimit::Limiter.new(apikey: "",
    shared_cache: Rails.cache,
    logger: Rails.logger,
    in_process_cache: ActiveSupport::Cache::MemoryStore.new(size: 1.megabytes)
)

@limiter.create_limit("event:pageload", 1, RateLimIt::HOURLY_ROLLING)
@limiter.create_limit("event:activation", 1, RateLimIt::INFINITE)


def track_event(event, user_id)
  if @limiter.feature_is_on_for?("Services::RateLimit", user_id)       
    return unless @limiter.pass?("event:#{event}:#{user_id}") 
  end
  actually_track_event(event, user_id)
end


track_event("pageload:home_page", 1) # will track
track_event("pageload:home_page", 1) # will skip for the next hour
track_event("activation", 1) # will track
track_event("activation", 1) # will skip forever


```

## Contributing to ratelimit-ruby
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2017 Jeff Dwyer. See LICENSE.txt for
further details.

