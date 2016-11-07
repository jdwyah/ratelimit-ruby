require 'ratelimit-ruby'

limiter = RateLimit::Limiter.new(apikey: "123321", account_id: 1)
#
# limiter.upsert_limit("grp", "2", RateLimit::MINUTELY)
#
# if limiter.check?("grp:4")
#   puts "do it!"
# else
#   puts "dont"
# end
#
#
# limiter.upsert_limit("hit_api", 10, RateLimit::MINUTELY_ROLLING)
#
# limit_result = limiter.acquire("hit_api", 6, allow_partial_response: true)
#
# limit_result.amount.times do # will get 6
#   puts "ACK"
# end
#
# limit_result = limiter.acquire("hit_api", 6, allow_partial_response: true)
# limit_result.amount.times do # will get 4
#   puts "ACK"
# end


limiter.upsert_semaphore("semaphore", 1, RateLimit::HOURLY_ROLLING)

5.times do |i|
  Thread.new do
    begin
      puts "A"
      limit_result = limiter.acquire_or_wait(key: "semaphore", acquire_amount: 1, max_wait_secs: 10)
      puts "DOING! #{i}"
      sleep(1)
      puts "RETURN! #{i}"
      limiter.return(limit_result)
    rescue RateLimit::WaitExceeded => e
      puts "never ran #{i}"
    end
  end
end


sleep(20)
