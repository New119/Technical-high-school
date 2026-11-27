module LifeGamble
  # プレイヤー1人分の状態（LP・マナ・メインカード・手札・ターンをまたぐ効果）
  class Player
    attr_reader :name, :config, :main_cards
    attr_accessor :lp, :mana, :hand, :hand_bonus, :next_turn, :current

    def initialize(name, config, cpu: false)
      @name       = name
      @config     = config
      @cpu        = cpu
      @lp         = config.max_lp
      @mana       = config.start_mana
      @main_cards = config.main_cards.transform_values { |c| c[:count] }
      @hand       = []
      @hand_bonus = 0                 # 「手札上限増加」による永続ボーナス
      @current    = self.class.fresh_modifiers  # 今のターンに効いている効果
      @next_turn  = self.class.fresh_modifiers  # 次の自分のターンに効く効果
    end

    # 「次のターン」系の効果をまとめたハッシュ
    def self.fresh_modifiers
      {
        hand_penalty: 0,        # 相手の「手札削減」
        ult_penalty: 0,         # 自分のウルトで捨てた枚数
        draw_blocked: false,    # 相手の「ドローブロック」
        danger_multiplier: 1.0, # 相手の「自爆率増加」
        immune: false           # 自分の「自爆無効」
      }
    end

    def cpu? = @cpu

    # 自分のターン開始時：予約されていた効果を「今のターン」に移す
    def begin_turn!
      @current   = @next_turn
      @next_turn = self.class.fresh_modifiers
    end

    def hand_limit
      return 0 if current[:draw_blocked]
      limit = config.base_hand_size + hand_bonus - current[:hand_penalty] - current[:ult_penalty]
      [ limit, 0 ].max
    end

    def main_left?(key = nil)
      key ? main_cards.fetch(key.to_sym).positive? : main_cards.values.sum.positive?
    end

    def available_mains
      main_cards.select { |_, n| n.positive? }.keys
    end

    def add_mana(amount)
      @mana = [ @mana + amount, config.mana_cap ].min
    end

    def lose_mana(amount)
      @mana = [ @mana - amount, 0 ].max
    end

    def take_damage(amount)
      @lp = [ @lp - amount, 0 ].max
    end

    def heal(amount)
      @lp = [ @lp + amount, config.max_lp ].min
    end

    def dead? = lp <= 0
  end
end
