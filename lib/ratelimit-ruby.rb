module RateLimit
  WAIT_INCR_MAX = 0.5
  ON_ERROR = [:log_and_pass, :log_and_hit, :throw]

  class WaitExceeded < StandardError
  end

  class Limiter
    def base_url(local)
      local ? 'http://localhost:8080' : 'http://www.ratelim.it'
    end

    def initialize(apikey:, on_error: :log_and_pass, logger: nil, debug: false, local: false, stats: nil)
      @logger = (logger || Logger.new($stdout)).tap do |log|
        log.progname = "RateLimit"
      end
      @stats = (stats || NoopStats.new)
      @on_error = on_error
      @conn = Faraday.new(:url => self.base_url(local)) do |faraday|
        faraday.request :json # form-encode POST params
        faraday.response :logger if debug
        faraday.options[:open_timeout] = 2
        faraday.options[:timeout] = 5
        faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      (username, pass) = apikey.split("|")
      @conn.basic_auth(username, pass)
    end


    def create_returnable_limit(group, total_tokens, seconds_to_refill_one_token)
      upsert_returnable_limit(group, total_tokens, seconds_to_refill_one_token, method: :post)
    end

    def upsert_returnable_limit(group, total_tokens, seconds_to_refill_one_token, method: :put)
      recharge_rate = (24*60*60)/seconds_to_refill_one_token
      recharge_policy = DAILY_ROLLING
      upsert(LimitDefinition.new(group, recharge_rate, recharge_policy, true, total_tokens), method)
    end

    # create only. does not overwrite if it already exists
    def create_limit(group, limit, policy, burst: nil)
      upsert(LimitDefinition.new(group, limit, policy, false, burst || limit), :post)
    end

    # upsert. overwrite whatever is there
    def upsert_limit(group, limit, policy, burst: nil)
      upsert(LimitDefinition.new(group, limit, policy, false, burst || limit), :put)
    end

    def pass?(group)
      result = acquire(group, 1)
      return result.passed
    end

    def acquire(group, acquire_amount, allow_partial_response: false)
      result = @conn.post '/api/v1/limitcheck', { acquireAmount: acquire_amount,
                                                  groups: [group],
                                                  allowPartialResponse: allow_partial_response }.to_json
      handle_failure(result) unless result.success?
      res =JSON.parse(result.body, object_class: OpenStruct)
      res.amount ||= 0
      @stats.increment("it.ratelim.limitcheck", tags: ["policy_group:#{res.policyGroup}", "pass:#{res.passed}"])
      res
    rescue => e
      handle_error(e)
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
        sleep += rand * WAIT_INCR_MAX
      end
      raise RateLimit::WaitExceeded
    end


    def return(limit_result)
      result = @conn.post '/api/v1/limitreturn',
                 { enforcedGroup: limit_result.enforcedGroup,
                   amount: limit_result.amount }.to_json
      handle_failure(result) unless result.success?
    rescue => e
      handle_error(e)
    end

    private

    def upsert(limit_definition, method)
      to_send = { limit: limit_definition.limit,
                  group: limit_definition.group,
                  burst: limit_definition.burst,
                  policyName: limit_definition.policy,
                  returnable: limit_definition.returnable }.to_json
      result= @conn.send(method, '/api/v1/limits', to_send)
      if !result.success?
        if method == :put
          handle_failure(result)
        elsif result.status != 409 # conflicts routinely expected on create
          handle_failure(result)
        end
      end
    rescue => e
      handle_error(e)
    end

    def handle_failure(result)
      case @on_error
      when :log_and_pass
        @logger.warn("returned #{result.status}")
        OpenStruct.new(passed: true)
      when :log_and_hit
        @logger.warn("returned #{result.status}")
        OpenStruct.new(passed: false)
      when :throw
        raise "#{result.status} calling RateLim.it"
      end
    end

    def handle_error(e)
      case @on_error
      when :log_and_pass
        @logger.warn(e)
        OpenStruct.new(passed: true)
      when :log_and_hit
        @logger.warn(e)
        OpenStruct.new(passed: false)
      when :throw
        raise e
      end
    end
  end

end

require 'faraday'
require 'faraday_middleware'
require 'logger'
require 'ratelimit/noop_stats'
require 'ratelimit/limit_definition'
