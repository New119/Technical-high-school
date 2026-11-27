module GamesHelper
  # 画面を開いた直後に表示するLP。直前のターンを再生するときは、再生前（操作前）のLPから始める
  def shown_lp(player)
    return player.lp unless replay

    replay[:lpBefore][game.players.index { |pl| pl.equal?(player) }]
  end

  def lp_percent(lp) = (lp * 100.0 / card_config.max_lp).round(1)

  # LPの残り具合で色を変える（JS の game_controller.js も同じ基準）
  def lp_class(lp)
    r = lp.to_f / card_config.max_lp
    if r > 0.5 then "high"
    elsif r > 0.2 then "mid"
    else "low"
    end
  end

  def pct(rate) = "#{(rate * 100).round(2)}%"

  # 対戦画面・交代画面の一番外側の要素。再生するターンがあれば、そのデータを JS に渡す
  def game_screen_tag(&block)
    data = { controller: "game", game_max_lp_value: card_config.max_lp }
    data[:game_replay_value] = replay.to_json if replay
    tag.div(class: ("replaying" if replay), data: data, &block)
  end

  # メインカードの効果の説明文
  def main_card_effect(card)
    if card[:damage_type] == "fixed"
      "#{card[:damage]}ダメージ"
    else
      "相手の現在LPの#{(card[:damage] * 100).round}%ダメージ"
    end
  end

  # プレイヤーにかかっている効果を [種類, ラベル] の配列にする
  def badges(player)
    list = []
    list << [ "buff", "手札上限+#{player.hand_bonus}" ] if player.hand_bonus.positive?
    if game.current_player.equal?(player) && !game.over?
      c = player.current
      list << [ "buff", "自爆無効中" ] if c[:immune]
      list << [ "debuff", "自爆率×#{c[:danger_multiplier].round(2)}中" ] if c[:danger_multiplier] > 1
    end
    n = player.next_turn
    list << [ "debuff", "次ターン 手札-#{n[:hand_penalty]}" ] if n[:hand_penalty].positive?
    list << [ "debuff", "次ターン 手札-#{n[:ult_penalty]}（ウルト代償）" ] if n[:ult_penalty].positive?
    list << [ "debuff", "次ターン 手札なし" ] if n[:draw_blocked]
    list << [ "debuff", "次ターン 自爆率×#{n[:danger_multiplier].round(2)}" ] if n[:danger_multiplier] > 1
    list << [ "buff", "次ターン 自爆無効" ] if n[:immune]
    list
  end

  # ターン終了時に処理される予定の効果名
  def pending_names
    game.turn.pending.map do |kind, key, _|
      kind == :support ? card_config.support(key)[:name] : "ウルト：#{card_config.ult(key)[:name]}"
    end
  end

  def ult_requirement(key)
    d = card_config.ult(key)[:discard]
    d == "all" ? "手札すべて" : "手札#{d}枚"
  end
end
