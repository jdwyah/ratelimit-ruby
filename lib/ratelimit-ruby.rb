module RateLimit
  WAIT_INCR_MAX = 0.5
  ON_ERROR = [:log_and_pass, :log_and_hit, :throw]

  class WaitExceeded < StandardError
  end

  class Limiter

    def initialize(apikey:,
                   on_error: :log_and_pass,
                   logger: nil,
                   debug: false,
                   stats: nil, # receives increment("it.ratelim.limitcheck", {:tags=>["policy_group:page_view", "pass:true"]})
                   shared_cache: nil, # Something that quacks like Rails.cache ideally memcached
                   in_process_cache: nil, # ideally ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)
                   use_expiry_cache: true, # must have shared_cache defined
                   local: false # local development
    )
      @on_error = on_error
      @logger = (logger || Logger.new($stdout)).tap do |log|
        log.progname = "RateLimit"
      end
      @stats = (stats || NoopStats.new)
      @shared_cache = (shared_cache || NoopCache.new)
      @in_process_cache = (in_process_cache || NoopCache.new)
      @use_expiry_cache = use_expiry_cache
      @conn = Faraday.new(:url => self.base_url(local)) do |faraday|
        faraday.request :json # form-encode POST params
        faraday.headers["accept"] = "application/json"
        faraday.response :logger if debug
        faraday.options[:open_timeout] = 2
        faraday.options[:timeout] = 5
        faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      (@account_id, pass) = apikey.split("|")
      @conn.basic_auth(@account_id, pass)
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

    def upsert(limit_definition, method)
      to_send = { limit: limit_definition.limit,
                  group: limit_definition.group,
                  burst: limit_definition.burst,
                  policyName: limit_definition.policy,
                  safetyLevel: limit_definition.safety_level,
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

    def pass?(group)
      result = acquire(group, 1)
      return result.passed
    end

    def acquire(group, acquire_amount, allow_partial_response: false)

      expiry_cache_key = "it.ratelim.expiry:#{group}"
      if @use_expiry_cache
        expiry = @shared_cache.read(expiry_cache_key)
        if !expiry.nil? && Integer(expiry) > Time.now.utc.to_f * 1000
          @stats.increment("it.ratelim.limitcheck.expirycache.hit", tags: [])
          return OpenStruct.new(passed: false, amount: 0)
        end
      end

      result = @conn.post '/api/v1/limitcheck', { acquireAmount: acquire_amount,
                                                  groups: [group],
                                                  allowPartialResponse: allow_partial_response }.to_json
      handle_failure(result) unless result.success?
      res =JSON.parse(result.body, object_class: OpenStruct)
      res.amount ||= 0

      @stats.increment("it.ratelim.limitcheck", tags: ["policy_group:#{res.policyGroup}", "pass:#{res.passed}"])
      if @use_expiry_cache
        reset = result.headers['X-Rate-Limit-Reset']
        @shared_cache.write(expiry_cache_key, reset) unless reset.nil?
      end
      return res
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
                            expiresAt: limit_result.expiresAt,
                            amount: limit_result.amount }.to_json
      handle_failure(result) unless result.success?
    rescue => e
      handle_error(e)
    end

    def feature_is_on?(feature)
      feature_is_on_for?(feature, nil)
    end

    def feature_is_on_for?(feature, lookup_key, attributes: [])
      @stats.increment("it.ratelim.featureflag.on", tags: ["feature:#{feature}"])

      cache_key = "it.ratelim.ff:#{feature}.#{lookup_key}.#{attributes}"
      @in_process_cache.fetch(cache_key, expires_in: 60) do
        next uncached_feature_is_on_for?(feature, lookup_key, attributes) if @shared_cache.class == NoopCache

        feature_obj = get_feature(feature)
        if feature_obj.nil?
          next false
        end

        attributes << lookup_key if lookup_key
        if (attributes & feature_obj.whitelisted).size > 0
          next true
        end

        if lookup_key
          next get_user_pct(feature, lookup_key) < feature_obj.pct
        end

        next feature_obj.pct > 0.999
      end
    end

    def base_url(local)
      local ? 'http://localhost:8080' : 'http://www.ratelim.it'
    end

    private

    def uncached_feature_is_on_for?(feature, lookup_key, attributes)
      to_send = {}
      to_send[:lookupKey] = lookup_key unless lookup_key.nil?
      to_send[:attributes] = attributes if attributes.any?
      result = @conn.get "/api/v1/featureflags/#{feature}/on", to_send
      @stats.increment("it.ratelim.featureflag.on.req", tags: ["success:#{result.success?}"])
      if result.success?
        result.body == "true"
      else
        handle_feature_failure(result)
      end
    end

    def get_feature(feature)
      get_all_features[feature]
    end

    def get_all_features
      @shared_cache.fetch("it.ratelim:get_all_features", expires_in: 60) do
        result = @conn.get "/api/v1/featureflags"
        @stats.increment("it.ratelim.featureflag.getall.req", tags: ["success:#{result.success?}"])
        if result.success?
          res =JSON.parse(result.body, object_class: OpenStruct)
          Hash[res.map { |r| [r.feature, r] }]
        else
          @logger.error("failed to fetch feature flags #{result.status}")
          {}
        end
      end
    end

    def get_user_pct(feature, lookup_key)
      int_value = Murmur3.murmur3_32("#{@account_id}#{feature}#{lookup_key}")
      int_value / 4294967294.0
    end

    def handle_failure(result)
      case @on_error
      when :log_and_pass
        @logger.warn("returned #{result.status}")
        OpenStruct.new(passed: true, amount: 0)
      when :log_and_hit
        @logger.warn("returned #{result.status}")
        OpenStruct.new(passed: false, amount: 0)
      when :throw
        raise "#{result.status} calling RateLim.it"
      end
    end

    def handle_error(e)
      case @on_error
      when :log_and_pass
        @logger.warn(e)
        OpenStruct.new(passed: true, amount: 0)
      when :log_and_hit
        @logger.warn(e)
        OpenStruct.new(passed: false, amount: 0)
      when :throw
        raise e
      end
    end


    def handle_feature_failure(result)
      case @on_error
      when :log_and_pass
        @logger.warn("returned #{result.status}")
        true
      when :log_and_hit
        @logger.warn("returned #{result.status}")
        false
      when :throw
        raise "#{result.status} calling feature flag RateLim.it"
      end
    end

  end

end

require 'faraday'
require 'faraday_middleware'
require 'logger'
require 'ratelimit/noop_stats'
require 'ratelimit/noop_cache'
require 'ratelimit/murmur3'
require 'ratelimit/limit_definition'
