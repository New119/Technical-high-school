module LifeGamble
  # ゲーム全体の進行を管理するクラス（画面表示には一切依存しない）
  #
  # 1ターンの流れ:
  #   1. ターン開始：手札をリロール（基準5枚 ± 各種効果）
  #   2. サポートカード / ウルト（1回）を好きなだけ使う ※効果は予約されるだけ
  #   3. メインカードを1枚使う（使い切っていればパス） → ターン終了処理へ
  #   4. ターン終了：予約効果 → メインのダメージ → 自爆抽選 → マナ+3
  class Game
    TurnState = Struct.new(:pending, :ult_used, :extra_turn, keyword_init: true)

    attr_reader :config, :players, :turn_number, :log, :winner, :end_reason, :turn, :rng

    def initialize(names: %w[プレイヤー1 プレイヤー2], cpu: [ false, false ],
                   config: Config.load, rng: Random.new, first: nil)
      @config  = config
      @rng     = rng
      @players = names.zip(cpu).map { |name, is_cpu| Player.new(name, config, cpu: is_cpu) }
      @current_index = first || rng.rand(2)
      @turn_number = 0
      @log = []
      @winner = nil
      @end_reason = nil
      add_log(:system, "ゲーム開始！ 先攻は#{current_player.name}")
      start_turn
    end

    # ---------- 状態の参照 ----------

    def current_player = players[@current_index]
    def opponent       = players[1 - @current_index]
    def over?          = !@end_reason.nil?
    def draw?          = over? && winner.nil?

    def recent_log(n = 30) = log.last(n)

    # メインカードを使った場合の、このターンの自爆確率（予約中の効果も含めた予測値）
    def death_rate(main_key, player = current_player)
      return 0.0 if main_key.nil?
      return 0.0 if player.current[:immune]

      rate = config.main(main_key)[:death_rate]
      rate *= pending_safety_multiplier if player.equal?(current_player)
      rate *= player.current[:danger_multiplier]
      [ rate, 1.0 ].min
    end

    # 「自爆無効」のターンかどうか
    def immune_now? = current_player.current[:immune]

    def ult_discard_count(key, player = current_player)
      d = config.ult(key)[:discard]
      d == "all" ? player.hand.size : d
    end

    def ult_usable?(key)
      return false if turn.ult_used
      d = config.ult(key)[:discard]
      d == "all" ? !current_player.hand.empty? : current_player.hand.size >= d
    end

    # ---------- プレイヤーの操作 ----------

    # 手札の index 番目のサポートカードを使う（マナは即消費、効果は終了時）
    def use_support(index)
      ensure_playing!
      p = current_player
      key = p.hand.fetch(index) { raise GameError, "そのカードは手札にありません" }
      card = config.support(key)
      raise GameError, "マナが足りません（必要#{card[:cost]} / 所持#{p.mana}）" if p.mana < card[:cost]

      p.mana -= card[:cost]
      p.hand.delete_at(index)
      turn.pending << [ :support, key ]
      add_log(:action, "#{p.name}は「#{card[:name]}」を使った（-#{card[:cost]}マナ）")
    end

    # ウルトを使う。discard_indices は捨てる手札の番号（"all"のウルトでは無視）
    def use_ult(key, discard_indices = [])
      ensure_playing!
      key = key.to_sym
      ult = config.ult(key)
      p = current_player
      raise GameError, "ウルトは1ターンに1回までです" if turn.ult_used

      if ult[:discard] == "all"
        raise GameError, "手札がないので使えません" if p.hand.empty?
        discard_indices = (0...p.hand.size).to_a
      else
        discard_indices = discard_indices.map(&:to_i).uniq
        if discard_indices.size != ult[:discard]
          raise GameError, "「#{ult[:name]}」には手札を#{ult[:discard]}枚選んで捨てる必要があります"
        end
        unless discard_indices.all? { |i| i >= 0 && i < p.hand.size }
          raise GameError, "存在しない手札が選ばれています"
        end
      end

      discarded = discard_indices.sort.reverse.map { |i| p.hand.delete_at(i) }
      turn.ult_used = true
      turn.pending << [ :ult, key, discarded.size ]
      add_log(:ult, "#{p.name}はウルト「#{ult[:name]}」を発動！（手札#{discarded.size}枚を破棄）")
    end

    # メインカードを使ってターンを終える
    def play_main(key)
      ensure_playing!
      key = key.to_sym
      p = current_player
      raise GameError, "不明なカードです" unless config.main_cards.key?(key)
      raise GameError, "「#{config.main(key)[:name]}」はもう残っていません" unless p.main_left?(key)

      end_turn(key)
    end

    # メインカードを使い切っているときだけ、パスしてターンを終えられる
    def pass_turn
      ensure_playing!
      raise GameError, "メインカードが残っている間は、毎ターン1枚使う必要があります" if current_player.main_left?

      end_turn(nil)
    end

    private

    def ensure_playing!
      raise GameError, "ゲームは終了しています" if over?
    end

    def start_turn
      @turn_number += 1
      @turn = TurnState.new(pending: [], ult_used: false, extra_turn: false)
      p = current_player
      p.begin_turn!
      p.hand = Array.new(p.hand_limit) { config.support_cards.keys.sample(random: rng) }

      add_log(:turn, "―― ターン#{turn_number}：#{p.name}の番（手札#{p.hand.size}枚 / マナ#{p.mana}）――")
      add_log(:effect, "ドローブロックでサポートカードが配られなかった") if p.current[:draw_blocked]
      add_log(:effect, "このターンは自爆しない！") if p.current[:immune]
      if p.current[:danger_multiplier] > 1
        add_log(:effect, "相手の妨害で、このターンの自爆確率が×#{fmt(p.current[:danger_multiplier])}")
      end
      add_log(:effect, "メインカードを使い切っているので、サポートのみのターン") unless p.main_left?
    end

    def end_turn(main_key)
      p = current_player
      o = opponent

      if main_key
        p.main_cards[main_key] -= 1
        add_log(:action, "#{p.name}はメインカード「#{config.main(main_key)[:name]}」を使った")
      else
        add_log(:action, "#{p.name}はパスした")
      end

      # ① 予約していた効果を順番に処理
      turn.pending.each { |effect| resolve(effect, p, o) }

      # ② メインカードのダメージ
      if main_key
        dmg = main_damage(main_key, o)
        o.take_damage(dmg)
        add_log(:damage, "#{o.name}に#{dmg}ダメージ！（残りLP #{o.lp}）", **lp_change(o, -dmg))
        return finish(p, "#{o.name}のLPが0になった") if o.dead?
      end

      # ③ 自爆の抽選（メインカードを使ったときだけ）
      if main_key
        rate = death_rate(main_key, p)
        roll = rng.rand
        if rate.zero?
          add_log(:safe, "自爆判定：自爆無効でセーフ", player: index_of(p))
        elsif roll < rate
          add_log(:death, "自爆判定（#{pct(rate)}）……#{p.name}は自爆した！", player: index_of(p))
          return finish(o, "#{p.name}が自爆した")
        else
          add_log(:safe, "自爆判定（#{pct(rate)}）……セーフ", player: index_of(p))
        end
      end

      # ④ マナ獲得
      p.add_mana(config.mana_per_turn)

      # ⑤ 両者メインカード切れならLP判定
      return judge_by_lp if players.none?(&:main_left?)

      # ⑥ 次のターンへ
      if turn.extra_turn
        add_log(:ult, "追加ターン！ もう一度#{p.name}の番")
      else
        @current_index = 1 - @current_index
      end
      start_turn
    end

    def resolve(effect, p, o)
      kind, key, discarded = effect
      if kind == :support
        resolve_support(key, p, o)
      else
        resolve_ult(key, discarded, p, o)
      end
    end

    def resolve_support(key, p, o)
      card = config.support(key)
      case key
      when :mana_boost
        p.add_mana(card[:value])
        add_log(:effect, "マナブースト：#{p.name}のマナ+#{card[:value]}（#{p.mana}）")
      when :hand_up
        p.hand_bonus += card[:value]
        add_log(:effect, "手札上限増加：#{p.name}の手札上限が永続的に+#{card[:value]}")
      when :hand_down
        o.next_turn[:hand_penalty] += card[:value]
        add_log(:effect, "手札削減：#{o.name}の次のターンの手札-#{card[:value]}")
      when :self_safety
        add_log(:effect, "自爆率低下：このターンの#{p.name}の自爆確率×#{fmt(card[:value])}")
      when :opponent_danger
        o.next_turn[:danger_multiplier] *= card[:value]
        add_log(:effect, "自爆率増加：#{o.name}の次のターンの自爆確率×#{fmt(card[:value])}")
      when :heal
        before = p.lp
        p.heal((config.max_lp * card[:value]).floor)
        add_log(:heal, "回復：#{p.name}のLP #{before}→#{p.lp}", **lp_change(p, p.lp - before))
      end
    end

    def resolve_ult(key, discarded, p, o)
      ult = config.ult(key)
      case key
      when :extra_turn
        turn.extra_turn = true
      when :draw_block
        o.next_turn[:draw_blocked] = true
        add_log(:effect, "ドローブロック：#{o.name}は次のターン手札が配られない")
      when :full_heal
        before = p.lp
        p.heal(config.max_lp)
        add_log(:heal, "LP全回復：#{p.name}のLP #{before}→#{p.lp}", **lp_change(p, p.lp - before))
      when :immunity
        p.next_turn[:immune] = true
        add_log(:effect, "自爆無効：#{p.name}は次の自分のターン自爆しない")
      when :mana_break
        before = o.mana
        o.lose_mana(ult[:value])
        add_log(:effect, "マナ破壊：#{o.name}のマナ #{before}→#{o.mana}")
      end
      # ウルトの代償：次の自分のターン、捨てた枚数だけ手札が減る
      p.next_turn[:ult_penalty] += discarded
    end

    def main_damage(key, target)
      card = config.main(key)
      case card[:damage_type]
      when "fixed"           then card[:damage]
      when "percent_current" then (target.lp * card[:damage]).floor
      else raise GameError, "不明なダメージ種別: #{card[:damage_type]}"
      end
    end

    # 予約中の「自爆率低下」をまとめた倍率
    def pending_safety_multiplier
      turn.pending
          .select { |kind, key| kind == :support && key == :self_safety }
          .reduce(1.0) { |m, _| m * config.support(:self_safety)[:value] }
    end

    def judge_by_lp
      a, b = players
      add_log(:system, "両者メインカードを使い切った！ LP判定：#{a.name} #{a.lp} / #{b.name} #{b.lp}")
      if a.lp == b.lp
        finish(nil, "LPが同じため引き分け")
      else
        w = [ a, b ].max_by(&:lp)
        finish(w, "LP判定で#{w.name}の勝ち")
      end
    end

    def finish(winner, reason)
      @winner = winner
      @end_reason = reason
      add_log(:system, winner ? "🏆 #{winner.name}の勝利！（#{reason}）" : "引き分け（#{reason}）")
      nil
    end

    # ログ1行分。data には画面の演出用の情報（誰のLPがいくつ変わったか等）を入れる
    #   player: 対象プレイヤーの番号（players の 0 か 1）
    #   lp:     変化した後のLP
    #   delta:  LPの増減（ダメージはマイナス）
    def add_log(type, text, **data)
      @log << { type: type, text: text, **data }
    end

    def lp_change(player, delta) = { player: index_of(player), lp: player.lp, delta: delta }
    def index_of(player) = players.index { |pl| pl.equal?(player) }

    def pct(rate) = "#{(rate * 100).round(2)}%"
    def fmt(num)  = num == num.to_i ? num.to_i.to_s : num.to_s
  end
end
