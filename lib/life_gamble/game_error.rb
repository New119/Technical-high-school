module LifeGamble
  # ルール上できない操作をしたときに投げるエラー（画面ではメッセージをそのまま表示する想定）
  class GameError < StandardError; end
end
