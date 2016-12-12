module RateLimit
  class WaitExceeded < StandardError
  end

  class Limiter
    def base_url(local)
      local ? 'http://localhost:8080' : 'http://www.ratelim.it'
    end

    def initialize(apikey:, local: false, debug: false)
      @conn = Faraday.new(:url => self.base_url(local)) do |faraday|
        faraday.request :json # form-encode POST params
        faraday.response :logger if debug
        faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      (username, pass) = apikey.split("|")
      @conn.basic_auth(username, pass)
    end


    def create_concurrency_limit(group, concurrent, timeout_seconds)
      upsert_concurrency_limit(group, concurrent, timeout_seconds, method: :post)
    end

    def upsert_concurrency_limit(group, concurrent, timeout_seconds, method: :put)
      recharge_rate = (24*60*60)/timeout_seconds
      recharge_policy = DAILY_ROLLING
      upsert(LimitDefinition.new(group, recharge_rate, recharge_policy, true, concurrent), method)
    end

    def create_limit(group, limit, policy, burst: nil)
      upsert(LimitDefinition.new(group, limit, policy, false, burst || limit), :post)
    end

    def upsert_limit(group, limit, policy, burst: nil)
      upsert(LimitDefinition.new(group, limit, policy, false, burst || limit), :put)
    end

    def check?(group)
      result = acquire(group, 1)
      return result.passed
    end

    def acquire(group, acquire_amount, allow_partial_response: false)
      result = @conn.post '/api/v1/limitcheck', { acquireAmount: acquire_amount,
                                                  groups: [group],
                                                  allowPartialResponse: allow_partial_response }.to_json
      res =JSON.parse(result.body, object_class: OpenStruct)
      res.amount ||= 0
      res
    end

    def acquire_or_wait(key:, acquire_amount:, max_wait_secs:, init_backoff: 0)
      start = Time.now
      sleep = init_backoff
      while Time.now - start < max_wait_secs
        sleep(sleep)
        res = acquire(key, acquire_amount)
        if res.passed
          return res
        end
        sleep += rand/2
      end
      raise RateLimit::WaitExceeded
    end


    def return(limit_result)
      @conn.post '/api/v1/limitreturn',
                 { enforcedGroup: limit_result.enforcedGroup,
                   amount: limit_result.amount }.to_json
      puts "RETURN #{result.body} #{result.status}"
    end

    private

    def upsert(limit_definition, method)
      to_send = { limit: limit_definition.limit,
                  group: limit_definition.group,
                  burst: limit_definition.burst,
                  policyName: limit_definition.policy,
                  returnable: limit_definition.returnable }.to_json
      result= @conn.send(method, '/api/v1/limits', to_send)
    end
  end

end

require 'faraday'
require 'faraday_middleware'
require 'ratelimit/limit_definition'
