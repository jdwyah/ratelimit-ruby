# ratelimit-ruby

Rate Limit your Ruby app using http://www.ratelim.it

```ruby
limiter =  RateLimit::Limiter.new(apikey: "APIKEY", account_id: ACCT_ID)

# only need to do this on startup
# limit to 1 per hour
limiter.upsert_limit(Limit.new("pageload", 1, RateLimIt::HOURLY_ROLLING))

if limiter.check?("pageload")
  do_hourly_thing()
end
```
See full documentation http://www.ratelim.it/documentation

## Supports

* RateLimits
* Millions of individual limits sharing the same policies
* WebUI for tweaking limits
* Logging
* Semaphores
* Infinite retention fo deduplication workflows


## Contributing to ratelimit-ruby
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2016 Jeff Dwyer. See LICENSE.txt for
further details.

