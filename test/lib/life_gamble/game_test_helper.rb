module LifeGamble
  # 乱数を思い通りに制御するためのテスト用オブジェクト
  #   rand(整数) → 常に0（先攻・配られるカードを固定）
  #   rand()     → floats を順番に返す（最後の値は使い回す）
  class FakeRng
    def initialize(*floats)
      @floats = floats.empty? ? [ 0.99 ] : floats
    end

    def rand(n = nil)
      return 0 if n.is_a?(Integer)
      @floats.size > 1 ? @floats.shift : @floats.first
    end
  end

  module GameTestHelper
    # 先攻はA。乱数は既定で 0.99（＝自爆しない）
    def new_game(*floats)
      LifeGamble::Game.new(names: %w[A B], rng: FakeRng.new(*floats), first: 0)
    end

    def a(game) = game.players[0]
    def b(game) = game.players[1]

    # 現在のプレイヤーの手札を差し替える
    def give(game, *keys)
      game.current_player.hand = keys
    end
  end
end
