# 進行中の対戦1つ分（ゲーム本体・対戦モード・交代画面を出すか・CPU）。
# DBには保存せず、サーバーのメモリ上に置く（サーバーを再起動すると消える）。
class Match
  # カードやルールの数値（config/cards.yml）。起動時に1回だけ読む
  CONFIG = LifeGamble::Config.load
  # メモリを使いすぎないよう、これを超えたら古い対戦から捨てる
  MAX_MATCHES = 200

  @store = {}
  @lock = Mutex.new

  class << self
    # 新しい対戦を始めて保存する。先攻がCPUならCPUのターンまで進める
    def start(mode:, names:)
      match = new(mode: mode, names: names)
      synchronize do
        @store[match.id] = match
        @store.shift while @store.size > MAX_MATCHES
        match.run_cpu!
      end
      match
    end

    def find(id)
      return nil if id.blank?

      synchronize { @store[id] }
    end

    # 同じ対戦を同時に操作して状態が壊れないよう、操作はこの中で行う
    def synchronize(&block)
      @lock.owned? ? block.call : @lock.synchronize(&block)
    end
  end

  attr_reader :id, :game, :mode
  attr_accessor :handoff

  def initialize(mode:, names:)
    @id = SecureRandom.hex(16)
    @mode = mode
    @game = LifeGamble::Game.new(names: names, cpu: [ false, cpu? ], config: CONFIG)
    @ai = LifeGamble::CpuAI.new
    @handoff = pvp? # 2人対戦は最初から交代画面を出す
  end

  def cpu? = mode == :cpu
  def pvp? = mode == :pvp

  # CPUの番が続く間、CPUに操作させる
  def run_cpu!
    @ai.play_turn(game) while !game.over? && game.current_player.cpu?
  end

  # プレイヤーの操作を実行し、CPUを動かす。2人対戦で手番が変わったら交代画面を出す
  def act!
    self.class.synchronize do
      before = game.current_player
      yield game
      run_cpu!
      self.handoff = true if pvp? && !game.over? && !game.current_player.equal?(before)
    end
  end
end
