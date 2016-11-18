module RateLimit
  class WaitExceeded < StandardError
  end

  class Limiter
    def base_url(local)
      local ? 'http://localhost:8080' : 'http://www.ratelim.it'
    end

    def initialize(apikey:, account_id:, local: false)
      @conn = Faraday.new(:url => self.base_url(local)) do |faraday|
        faraday.request :json # form-encode POST params
        faraday.response :logger # log requests to STDOUT
        faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      puts "basic #{account_id} #{apikey}"
      @conn.basic_auth(account_id, apikey)
    end

    def upsert_semaphore(group, limit, policy)
      upsert(LimitDefinition.new(group, limit, policy, true))
    end

    def upsert_limit(group, limit, policy)
      upsert(LimitDefinition.new(group, limit, policy, false))
    end

    def check?(group)
      result = acquire(group, 1)
      return result.passed
    end

    def acquire(group, acquire_amount, allow_partial_response: false)
      result = @conn.post '/api/v1/limitcheck', { acquireAmount: acquire_amount,
                                                  groups: [group],
                                                  allowPartialResponse: allow_partial_response }.to_json
      puts result.body
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
        sleep += rand
      end
      raise RateLimit::WaitExceeded
    end


    def return(limit_result)
      @conn.post '/api/v1/limitreturn',
                 { enforcedGroup: limit_result.enforcedGroup,
                   amount: limit_result.amount }.to_json
      puts result.body
    end

    private

    def upsert(limit_definition)
      to_send = { limit: limit_definition.limit,
                  group: limit_definition.group,
                  policyName: limit_definition.policy,
                  returnable: limit_definition.returnable }.to_json
      result= @conn.post '/api/v1/limits', to_send

      puts result.body
    end
  end

end

require 'faraday'
require 'faraday_middleware'
require 'ratelimit/limit_definition'
