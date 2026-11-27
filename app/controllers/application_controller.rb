class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_match, :card_config

  private

  # このブラウザで進行中の対戦（なければ nil）
  def current_match
    return @current_match if defined?(@current_match)

    @current_match = Match.find(session[:match_id])
  end

  # カードやルールの数値
  def card_config = Match::CONFIG
end
