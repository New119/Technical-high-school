# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/card_game"

class CardGameTest < Minitest::Test
  def test_readme_values_are_preserved
    assert_equal 4_000, CardGame::Rules::INITIAL_LP
    assert_equal 1, CardGame::Rules::MANA_GAIN_PER_FINISHED_TURN
    assert_equal 5, CardGame::Rules::BASE_SUPPORT_HAND_SIZE
    assert_equal({small: 4, medium: 2, large: 1}, counts)
    assert_equal [4, 15, 50], [:small, :medium, :large].map {
      |type| CardGame::Rules.main_card(type).fetch(:death_probability_percent)
    }
  end

  def test_fixed_damage_for_small_and_medium
    assert_equal 100, CardGame::Damage.for_card(:small, opponent_lp: 4_000)
    assert_equal 800, CardGame::Damage.for_card(:medium, opponent_lp: 4_000)
  end

  def test_large_damage_is_exact_without_guessing_rounding
    assert_equal 3_600, CardGame::Damage.for_card(:large, opponent_lp: 4_000)
    assert_equal Rational(9, 10), CardGame::Damage.for_card(:large, opponent_lp: 1)
  end

  def test_player_starts_with_readme_lp_and_card_counts
    player = CardGame::PlayerState.new(initial_mana: 0)
    assert_equal 4_000, player.lp
    assert_equal 0, player.mana
    assert_equal({small: 4, medium: 2, large: 1}, player.remaining_main_cards)
  end

  def test_used_main_cards_are_consumed_without_being_replenished
    player = CardGame::PlayerState.new(initial_mana: 0)
    4.times { player.use_main_card!(:small) }
    assert_equal 0, player.remaining_main_cards[:small]
    assert_raises(ArgumentError) { player.use_main_card!(:small) }
    assert_equal 2, player.remaining_main_cards[:medium]
  end

  def test_card_collection_cannot_be_mutated_from_outside
    player = CardGame::PlayerState.new(initial_mana: 0)
    assert_raises(FrozenError) { player.remaining_main_cards[:small] = 20 }
    assert_equal 4, player.remaining_main_cards[:small]
  end

  def test_mana_gain_is_explicit_and_one_per_call
    player = CardGame::PlayerState.new(initial_mana: 3)
    assert_equal 4, player.gain_mana_after_finished_turn!
    assert_equal 4, player.mana
  end

  def test_nonnegative_fixed_damage_reduces_lp
    player = CardGame::PlayerState.new(initial_mana: 0)
    player.apply_damage!(100)
    assert_equal 3_900, player.lp
    player.apply_damage!(9_999)
    assert_equal 0, player.lp
  end

  def test_invalid_cards_and_inputs_fail
    player = CardGame::PlayerState.new(initial_mana: 0)
    assert_raises(ArgumentError) { player.use_main_card!(:unknown) }
    assert_raises(ArgumentError) { player.apply_damage!(-1) }
    assert_raises(ArgumentError) { CardGame::PlayerState.new(initial_mana: -1) }
    assert_raises(ArgumentError) { CardGame::Damage.for_card(:large, opponent_lp: -1) }
  end

  private

  def counts
    CardGame::Rules::MAIN_CARDS.transform_values { |rule| rule.fetch(:count) }
  end
end
