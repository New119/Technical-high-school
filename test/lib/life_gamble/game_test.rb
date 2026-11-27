require "test_helper"
require_relative "game_test_helper"

module LifeGamble
  class GameTest < ActiveSupport::TestCase
    include GameTestHelper

    test "初期状態" do
      g = new_game
      assert_equal 6000, a(g).lp
      assert_equal 3, a(g).mana
      assert_equal 5, a(g).hand.size
      assert_equal({ small: 4, medium: 2, large: 1 }, a(g).main_cards)
      assert_same a(g), g.current_player
    end

    test "小は1000ダメージでマナ3獲得して交代" do
      g = new_game
      g.play_main(:small)
      assert_equal 5000, b(g).lp
      assert_equal 6, a(g).mana # 初期3 + 3
      assert_equal 3, a(g).main_cards[:small]
      assert_same b(g), g.current_player
    end

    test "大は相手の現在LPの90パーセント" do
      g = new_game
      b(g).lp = 4000
      g.play_main(:large)
      assert_equal 400, b(g).lp
    end

    test "自爆抽選に当たると負け" do
      g = new_game(0.01)
      g.play_main(:small)
      assert g.over?
      assert_same b(g), g.winner
      assert_match(/自爆/, g.end_reason)
    end

    test "自爆抽選に外れればセーフ" do
      g = new_game(0.05)
      g.play_main(:small)
      refute g.over?
    end

    test "自爆率低下はそのターンの抽選に効く" do
      g = new_game(0.3) # 大の50%なら自爆、25%ならセーフ
      a(g).mana = 3
      give(g, :self_safety)
      g.use_support(0)
      assert_in_delta 0.25, g.death_rate(:large)
      g.play_main(:large)
      refute g.over?
    end

    test "自爆率増加は相手の次のターンに効く" do
      g = new_game
      a(g).mana = 4
      give(g, :opponent_danger)
      g.use_support(0)
      g.play_main(:small)
      assert_in_delta 0.08, g.death_rate(:small) # Bの番
      g.play_main(:small)
      g.play_main(:small)
      assert_in_delta 0.04, g.death_rate(:small) # Bの次の番では元に戻る
    end

    test "マナ不足では使えない" do
      g = new_game
      a(g).mana = 2
      give(g, :heal)
      assert_raises(LifeGamble::GameError) { g.use_support(0) }
    end

    test "マナの上限は10" do
      g = new_game
      a(g).mana = 9
      g.play_main(:small)
      assert_equal 10, a(g).mana
    end

    test "マナブーストは終了時に5マナ" do
      g = new_game
      a(g).mana = 2
      give(g, :mana_boost)
      g.use_support(0)
      assert_equal 0, a(g).mana
      g.play_main(:small)
      assert_equal 8, a(g).mana # +5 +3
    end

    test "手札上限増加は永続" do
      g = new_game
      a(g).mana = 3
      give(g, :hand_up)
      g.use_support(0)
      g.play_main(:small)
      g.play_main(:small) # B
      assert_equal 6, a(g).hand.size
      g.play_main(:small)
      g.play_main(:small) # B
      assert_equal 6, a(g).hand.size
    end

    test "手札削減は相手の次のターンだけ" do
      g = new_game
      a(g).mana = 2
      give(g, :hand_down)
      g.use_support(0)
      g.play_main(:small)
      assert_equal 4, b(g).hand.size
      g.play_main(:small)
      g.play_main(:small)
      assert_equal 5, b(g).hand.size
    end

    test "回復は最大LPの25パーセントで上限を超えない" do
      g = new_game
      a(g).mana = 6
      a(g).lp = 5000
      give(g, :heal, :heal)
      g.use_support(0)
      g.use_support(0)
      g.play_main(:small)
      assert_equal 6000, a(g).lp
    end

    test "追加ターンとウルトの代償" do
      g = new_game
      g.use_ult(:extra_turn, [ 0, 1, 2 ])
      assert_equal 2, a(g).hand.size
      g.play_main(:small)
      assert_same a(g), g.current_player
      assert_equal 2, a(g).hand.size # 5 - 捨てた3枚
      g.play_main(:small)
      assert_same b(g), g.current_player
    end

    test "ドローブロック" do
      g = new_game
      g.use_ult(:draw_block, [ 0, 1, 2, 3 ])
      g.play_main(:small)
      assert_equal 0, b(g).hand.size
    end

    test "LP全回復" do
      g = new_game
      a(g).lp = 100
      g.use_ult(:full_heal, [ 0, 1, 2, 3 ])
      g.play_main(:small)
      assert_equal 6000, a(g).lp
    end

    test "自爆無効は次の自分のターンに効く" do
      g = new_game(0.99, 0.99, 0.0) # 3回目の抽選(Aの2ターン目)は必ず当たる値
      g.use_ult(:immunity)
      assert_empty a(g).hand
      assert_in_delta 0.04, g.death_rate(:small) # このターンはまだ無効ではない
      g.play_main(:small)
      g.play_main(:small) # B
      assert g.immune_now?
      assert_equal 0, a(g).hand.size # 5枚捨てたので次の手札は0枚
      g.play_main(:large)
      refute g.over? || a(g).dead?, "自爆無効なので大でも生き残る"
      assert_equal 500, b(g).lp # 6000-1000=5000 → 大で90%削って500
    end

    test "マナ破壊は0未満にならない" do
      g = new_game
      b(g).mana = 4
      g.use_ult(:mana_break, [ 0, 1, 2, 3 ])
      g.play_main(:small)
      assert_equal 0, b(g).mana
    end

    test "ウルトは1ターン1回で枚数が合わないと使えない" do
      g = new_game
      assert_raises(LifeGamble::GameError) { g.use_ult(:full_heal, [ 0 ]) }
      g.use_ult(:full_heal, [ 0, 1, 2, 3 ])
      assert_raises(LifeGamble::GameError) { g.use_ult(:full_heal, [ 0, 1, 2, 3 ]) }
    end

    test "メインが残っている間はパスできない" do
      g = new_game
      assert_raises(LifeGamble::GameError) { g.pass_turn }
    end

    test "使い切ったカードは使えない" do
      g = new_game
      a(g).main_cards[:large] = 0
      assert_raises(LifeGamble::GameError) { g.play_main(:large) }
    end

    test "LPを0にすれば勝ち" do
      g = new_game
      b(g).lp = 1000
      g.play_main(:small)
      assert_same a(g), g.winner
    end

    test "両者メイン切れでLP判定" do
      g = new_game
      a(g).main_cards.merge!(small: 1, medium: 0, large: 0)
      b(g).main_cards.merge!(small: 1, medium: 0, large: 0)
      g.play_main(:small)
      g.play_main(:small)
      assert g.over?
      assert g.draw?, "お互い1000ずつ削ったので同点→引き分け"

      g = new_game
      a(g).main_cards.merge!(small: 1, medium: 0, large: 0)
      b(g).main_cards.merge!(small: 0, medium: 0, large: 0)
      g.play_main(:small)
      assert_same a(g), g.winner
    end

    test "メイン切れのプレイヤーはサポートのみのターン" do
      g = new_game
      a(g).main_cards.merge!(small: 0, medium: 0, large: 0)
      g.pass_turn
      refute g.over?
      assert_equal 6, a(g).mana
      assert_same b(g), g.current_player
    end
  end
end
