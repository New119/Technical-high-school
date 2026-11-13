# frozen_string_literal: true

module CardGame
  # Numbers copied from the team's README. This module intentionally does not
  # decide whose death is checked, when it is checked, or how probabilities stack.
  module Rules
    INITIAL_LP = 4_000
    MANA_GAIN_PER_FINISHED_TURN = 1
    BASE_SUPPORT_HAND_SIZE = 5

    MAIN_CARDS = {
      small: { count: 4, death_probability_percent: 4, damage: 100 },
      medium: { count: 2, death_probability_percent: 15, damage: 800 },
      large: { count: 1, death_probability_percent: 50, damage_ratio: Rational(9, 10) }
    }.transform_values(&:freeze).freeze

    def self.main_card(type)
      MAIN_CARDS.fetch(type) do
        raise ArgumentError, "unknown main card: #{type.inspect}"
      end
    end
  end
end
