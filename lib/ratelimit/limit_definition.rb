module RateLimit
  SECONDLY="SECONDLY".freeze
  MINUTELY="MINUTELY".freeze
  MINUTELY_ROLLING="MINUTELY_ROLLING".freeze
  HOURLY="HOURLY".freeze
  HOURLY_ROLLING="HOURLY_ROLLING".freeze
  DAILY="DAILY".freeze
  DAILY_ROLLING="DAILY_ROLLING".freeze
  MONTHLY="MONTHLY".freeze
  INFINITE="INFINITE".freeze
  POLICIES = [SECONDLY, MINUTELY, MINUTELY_ROLLING, HOURLY, HOURLY_ROLLING, DAILY, DAILY_ROLLING, MINUTELY, INFINITE]

  L4_BEST_EFFORT = "L4_BEST_EFFORT"
  L5_BOMBPROOF = "L5_BOMBPROOF"
  SAFETY_LEVELS = [L4_BEST_EFFORT, L5_BOMBPROOF]

  class LimitDefinition
    attr_reader :limit, :group, :policy, :returnable, :burst
    attr_accessor :safety_level

    def initialize(group, limit, policy, returnable, burst)
      raise "Invalid Policy" unless POLICIES.include? policy
      @limit = limit
      @group = group
      @policy = policy
      @returnable = returnable
      @burst = burst
    end
  end
end
