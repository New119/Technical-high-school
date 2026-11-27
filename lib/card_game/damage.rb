# frozen_string_literal: true

module CardGame
  # Calculates damage without resolving a turn or making an instant-death draw.
  # The large card returns a Rational because the 90% rounding rule is unknown.
  module Damage
    def self.for_card(type, opponent_lp:)
      unless opponent_lp.is_a?(Integer) && opponent_lp >= 0
        raise ArgumentError, "opponent_lp must be a non-negative Integer"
      end

      rule = Rules.main_card(type)
      return rule.fetch(:damage) if rule.key?(:damage)

      opponent_lp * rule.fetch(:damage_ratio)
    end
  end
end
