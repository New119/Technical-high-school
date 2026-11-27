# 対戦画面。ゲームのルールは lib/life_gamble に任せ、ここは「表示」と「操作の受け渡し」だけを担当する。
class GamesController < ApplicationController
  NAME_MAX_LENGTH = 12

  before_action :require_match, except: :create

  helper_method :game, :me, :rival, :my_turn?, :replay

  def create
    mode = params[:mode] == "pvp" ? :pvp : :cpu
    names = [
      player_name(params[:name1], "プレイヤー1"),
      player_name(params[:name2], mode == :cpu ? "CPU" : "プレイヤー2")
    ]
    match = Match.start(mode: mode, names: names)
    session[:match_id] = match.id
    @current_match = match
    act # 先攻がCPUなら、CPUのターンを進める
  end

  def show
    render(current_match.handoff && !game.over? ? :handoff : :show)
  end

  def handoff
    current_match.handoff = false
    redirect_to game_path
  end

  def support
    act { |g| g.use_support(params[:index].to_i) }
  end

  def ult
    act do |g|
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

  def require_match
    redirect_to root_path unless current_match
  end

  # 操作を実行して対戦画面に戻る。ターンが終わったら、結果を再生するための情報を次の画面に渡す
  def act(&block)
    snapshot = current_match.act!(&block)
    flash[:replay] = snapshot if snapshot
    redirect_to game_path
  rescue LifeGamble::GameError => e
    redirect_to game_path, alert: e.message
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
  def replay
    return @replay if defined?(@replay)

    snapshot = flash[:replay]
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

  # 画面の手前側に表示するプレイヤー（CPU戦では人間、2人対戦では今の手番の人）
  def me
    return game.current_player if current_match.pvp?

    game.players.find { |p| !p.cpu? }
  end

  def rival = game.players.find { |p| !p.equal?(me) }

  # 今が手前のプレイヤーの操作ターンか
  def my_turn? = !game.over? && game.current_player.equal?(me)
end
