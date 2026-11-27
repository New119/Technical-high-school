module LifeGamble
  # シンプルなルールベースのCPU。Game の公開メソッドだけを使って1ターン分プレイする。
  class CpuAI
    # 手札の優先度（大きいほど先に使う / ウルトで捨てるときは小さい順に捨てる）
    BASE_PRIORITY = {
      heal: 50, self_safety: 40, opponent_danger: 35,
      mana_boost: 20, hand_down: 15, hand_up: 10
    }.freeze

    def initialize(rng: Random.new)
      @rng = rng
    end

    def play_turn(game)
      return if game.over?

      me  = game.current_player
      opp = game.opponent
      main = choose_main(game, me, opp)

      try_ult(game, me, opp, main)
      use_supports(game, me, opp, main)

      main ? game.play_main(main) : game.pass_turn
    end

    private

    # どのメインカードを使うか
    def choose_main(game, me, opp)
      avail = me.available_mains
      return nil if avail.empty?

      dmg = ->(k) { k == :large ? (opp.lp * 0.9).floor : game.config.main(k)[:damage] }
      # とどめを刺せるなら、一番安全なカードで
      finisher = avail.sort_by { |k| game.config.main(k)[:death_rate] }.find { |k| dmg.(k) >= opp.lp }
      return finisher if finisher

      # 自爆無効のターンは大を使うチャンス
      return :large if avail.include?(:large) && me.current[:immune]

      # 自爆率低下カードを持っていて相手のLPが多いなら大
      if avail.include?(:large) && opp.lp >= 4000 && me.hand.include?(:self_safety) && me.mana >= 3
        return :large
      end

      # 負けているときは中で攻める
      return :medium if avail.include?(:medium) && me.lp <= opp.lp

      # 基本は小 → 中 → 大の順に消費（大は最後に回す）
      %i[small medium large].find { |k| avail.include?(k) }
    end

    def try_ult(game, me, opp, main)
      hand = me.hand.size
      choice =
        if me.lp <= 2500 && game.ult_usable?(:full_heal)
          :full_heal
        elsif opp.mana >= 6 && hand >= 4 && unaffordable_count(game, me) >= 2 && game.ult_usable?(:mana_break)
          :mana_break
        elsif me.main_left?(:large) && main != :large && hand.between?(1, 2) &&
              !me.current[:immune] && game.ult_usable?(:immunity)
          :immunity # 次のターンに大を安全に撃つ準備
        elsif opp.lp <= 2000 && me.main_cards.values.sum >= 2 && game.ult_usable?(:extra_turn)
          :extra_turn
        elsif opp.mana >= 7 && hand >= 5 && @rng.rand < 0.3 && game.ult_usable?(:draw_block)
          :draw_block
        end
      return unless choice

      n = game.ult_discard_count(choice)
      # 優先度の低いカードから捨てる
      idx = me.hand.each_with_index.sort_by { |k, _| priority(k, game, me, opp, main) }.first(n).map(&:last)
      game.use_ult(choice, idx)
    end

    def use_supports(game, me, opp, main)
      loop do
        candidates = me.hand.each_with_index
                       .select { |k, _| useful?(k, game, me, opp, main) }
                       .select { |k, _| me.mana >= game.config.support(k)[:cost] }
        break if candidates.empty?

        _, idx = candidates.max_by { |k, _| priority(k, game, me, opp, main) }
        game.use_support(idx)
      end
    end

    def useful?(key, game, me, opp, main)
      case key
      when :heal            then me.lp <= game.config.max_lp - 1500
      when :self_safety     then main && main != :small && !me.current[:immune]
      when :opponent_danger then opp.main_left?
      when :hand_up         then me.main_cards.values.sum >= 3
      else true
      end
    end

    def priority(key, game, me, opp, main)
      p = BASE_PRIORITY.fetch(key, 0)
      p += 30 if key == :self_safety && main == :large
      p -= 100 unless useful?(key, game, me, opp, main)
      p
    end

    def unaffordable_count(game, me)
      me.hand.count { |k| game.config.support(k)[:cost] > me.mana }
    end
  end
end
