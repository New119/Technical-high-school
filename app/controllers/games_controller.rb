# 対戦画面。ゲームのルールは lib/life_gamble に任せ、ここは「表示」と「操作の受け渡し」だけを担当する。
class GamesController < ApplicationController
  NAME_MAX_LENGTH = 12

  before_action :require_match, except: :create

  helper_method :game, :me, :rival, :my_turn?

  def create
    mode = params[:mode] == "pvp" ? :pvp : :cpu
    names = [
      player_name(params[:name1], "プレイヤー1"),
      player_name(params[:name2], mode == :cpu ? "CPU" : "プレイヤー2")
    ]
    match = Match.start(mode: mode, names: names)
    session[:match_id] = match.id
    redirect_to game_path
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

  def act(&block)
    current_match.act!(&block)
    redirect_to game_path
  rescue LifeGamble::GameError => e
    redirect_to game_path, alert: e.message
  end

  def player_name(raw, default)
    name = raw.to_s.strip[0, NAME_MAX_LENGTH]
    name.presence || default
  end

  def game = current_match.game

  # 画面の手前側に表示するプレイヤー（CPU戦では人間、2人対戦では今の手番の人）
  def me
    return game.current_player if current_match.pvp?

    game.players.find { |p| !p.cpu? }
  end

  def rival = game.players.find { |p| !p.equal?(me) }

  # 今が手前のプレイヤーの操作ターンか
  def my_turn? = !game.over? && game.current_player.equal?(me)
end
