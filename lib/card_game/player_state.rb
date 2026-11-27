# frozen_string_literal: true

module CardGame
  # Keeps only explicitly described per-player state. The caller must supply
  # initial mana because the README specifies its gain, not its initial value.
  class PlayerState
    attr_reader :lp, :mana

    def initialize(initial_mana:)
      unless initial_mana.is_a?(Integer) && initial_mana >= 0
        raise ArgumentError, "initial_mana must be a non-negative Integer"
      end

      @lp = Rules::INITIAL_LP
      @mana = initial_mana
      @remaining_main_cards = Rules::MAIN_CARDS.transform_values { |rule| rule.fetch(:count) }
    end

    def remaining_main_cards
      @remaining_main_cards.dup.freeze
    end

    def use_main_card!(type)
      Rules.main_card(type)
      raise ArgumentError, "no #{type} cards remaining" if @remaining_main_cards.fetch(type).zero?

      @remaining_main_cards[type] -= 1
    end

    def gain_mana_after_finished_turn!
      @mana += Rules::MANA_GAIN_PER_FINISHED_TURN
    end

    def apply_damage!(amount)
      unless amount.is_a?(Integer) && amount >= 0
        raise ArgumentError, "damage must be a non-negative Integer"
      end

      @lp = [@lp - amount, 0].max
    end
  end
end
