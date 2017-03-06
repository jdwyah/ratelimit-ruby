module RateLimit
  SECONDLY_ROLLING="SECONDLY_ROLLING".freeze
  MINUTELY_ROLLING="MINUTELY_ROLLING".freeze
  HOURLY_ROLLING="HOURLY_ROLLING".freeze
  DAILY_ROLLING="DAILY_ROLLING".freeze
  MONTHLY_ROLLING="MONTHLY_ROLLING".freeze
  YEARLY_ROLLING="YEARLY_ROLLING".freeze
  INFINITE="INFINITE".freeze
  POLICIES = [SECONDLY_ROLLING, MINUTELY_ROLLING, HOURLY_ROLLING, DAILY_ROLLING, MONTHLY_ROLLING, YEARLY_ROLLING, INFINITE]

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
