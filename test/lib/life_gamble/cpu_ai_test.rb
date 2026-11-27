require "test_helper"

module LifeGamble
  class CpuAITest < ActiveSupport::TestCase
    test "CPU同士で最後までエラーなく対戦できる" do
      500.times do |seed|
        rng = Random.new(seed)
        g = LifeGamble::Game.new(names: %w[X Y], cpu: [ true, true ], rng: rng)
        ai = LifeGamble::CpuAI.new(rng: rng)
        100.times { break if g.over?; ai.play_turn(g) }
        assert g.over?, "seed #{seed} で決着がつかない"
      end
    end
  end
end
