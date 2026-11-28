# 対戦画面。ゲームのルールは lib/life_gamble に任せ、ここは「表示」と「操作の受け渡し」だけを担当する。
class GamesController < ApplicationController
  NAME_MAX_LENGTH = 12

  before_action :require_match, except: %i[create room]
  before_action :require_game, except: %i[create room show leave status]

  helper_method :game, :me, :rival, :my_turn?, :replay

  def create
    mode = params[:mode] == "pvp" ? :pvp : :cpu
    names = [
      player_name(params[:name1], "プレイヤー1"),
      player_name(params[:name2], mode == :cpu ? "CPU" : "プレイヤー2")
    ]
    match = Match.start(mode: mode, names: names)
    session[:match_id] = match.id
    session.delete(:seat_token)
    @current_match = match
    act # 先攻がCPUなら、CPUのターンを進める
  end

  # オンライン対戦：合言葉の部屋に入る。まだ部屋がなければ作って相手を待つ
  def room
    match, token = Match.enter_room(passphrase: params[:passphrase],
                                    name: player_name(params[:name], "プレイヤー"),
                                    rejoin_id: session[:match_id])
    session[:match_id] = match.id
    session[:seat_token] = token if token
    redirect_to game_path
  rescue Match::RoomError => e
    redirect_to root_path, alert: e.message
  end

  def show
    if current_match.waiting?
      render :waiting
    else
      render(current_match.handoff && !game.over? ? :handoff : :show)
    end
  end

  # オンライン対戦：相手が来る前に部屋を閉じてタイトルに戻る
  def leave
    Match.close_room(current_match) if current_match.waiting?
    session.delete(:match_id)
    session.delete(:seat_token)
    redirect_to root_path
  end

  # オンライン対戦：画面が古くなっていないか調べるための状態（相手が操作すると version が変わる）
  def status
    render json: { version: current_match.version }
  end

  def handoff
    current_match.handoff = false
    redirect_to game_path
  end

  def support
    act(announce: true) { |g| g.use_support(params[:index].to_i) }
  end

  def ult
    act(announce: true) do |g|
      raise LifeGamble::GameError, "ウルトを選んでください" if params[:ult].blank?

      g.use_ult(params[:ult], Array(params[:discard]))
    end
  end

  def play_main
    act { |g| g.play_main(params[:card].to_s) }
  end

  def pass
    act(&:pass_turn)
  end

  private

  # 対戦がない（オンライン対戦では、自分の座席がない）ならタイトルに戻す
  def require_match
    return if current_match && (!current_match.online? || seat)

    redirect_to root_path
  end

  # 相手を待っている間は、カードの操作はできない
  def require_game
    redirect_to game_path if current_match.waiting?
  end

  # オンライン対戦での自分の座席（0 か 1）
  def seat
    return @seat if defined?(@seat)

    @seat = current_match&.seat_of(session[:seat_token])
  end

  # 操作を実行して対戦画面に戻る。ターンが終わったら、結果を再生するための情報を次の画面に渡す
  #   announce: true なら、使ったカードを「〜を使いました」と知らせる
  def act(announce: false, &block)
    snapshot = current_match.act!(seat: seat) do |g|
      # オンライン対戦では、相手の番に操作できないようにする
      raise LifeGamble::GameError, "相手の番です。相手の操作を待ってください" if current_match.online? && !my_turn?

      block&.call(g)
    end
    if snapshot
      flash[:replay] = snapshot
    elsif announce
      flash[:notice] = used_card_notice
    end
    redirect_to game_path
  rescue LifeGamble::GameError => e
    redirect_to game_path, alert: e.message
  end

  # 直前に使ったサポートカード・ウルトのお知らせ文
  def used_card_notice
    kind, key, discarded = game.turn.pending.last
    if kind == :support
      card = card_config.support(key)
      "「#{card[:name]}」を使いました（マナ -#{card[:cost]}）。効果はターン終了時に発動します"
    else
      "ウルト「#{card_config.ult(key)[:name]}」を発動しました（手札#{discarded}枚を捨てた）。効果はターン終了時に発動します"
    end
  end

  def player_name(raw, default)
    name = raw.to_s.strip[0, NAME_MAX_LENGTH]
    name.presence || default
  end

  def game = current_match.game

  # 直前のターンの結果を再生するためのデータ（再生するものがなければ nil）
  #   lpBefore: 操作する前の両者のLP
  #   from:     ログの何行目から再生するか
  #   events:   再生するログ（player: 対象, lp: 変化後のLP, delta: 増減）
  # オンライン対戦では、相手のターンの結果も、次に画面を開いたときに再生する
  def replay
    return @replay if defined?(@replay)

    snapshot = flash[:replay] || (current_match.take_replay(seat) if current_match.online?)
    events = snapshot && game.log[snapshot["from"].to_i..]
    @replay =
      if events.present?
        {
          lpBefore: snapshot["lp"],
          from: snapshot["from"].to_i,
          events: events.map { |e| e.slice(:type, :text, :player, :lp, :delta) }
        }
      end
  end

  # 画面の手前側に表示するプレイヤー
  # （CPU戦では人間、2人対戦では今の手番の人、オンライン対戦では自分）
  def me
    return game.players[seat] if current_match.online?
    return game.current_player if current_match.pvp?

    game.players.find { |p| !p.cpu? }
  end

  def rival = game.players.find { |p| !p.equal?(me) }

  # 今が手前のプレイヤーの操作ターンか
  def my_turn? = !game.over? && game.current_player.equal?(me)
end
