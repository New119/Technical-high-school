# 進行中の対戦1つ分（ゲーム本体・対戦モード・交代画面を出すか・CPU）。
# DBには保存せず、サーバーのメモリ上に置く（サーバーを再起動すると消える）。
#
# 対戦モード
#   :cpu    CPUと対戦
#   :pvp    1台の画面を2人で交代しながら対戦
#   :online 合言葉で部屋を作り、別々の端末から対戦（座席ごとの合鍵 seat_token で本人を見分ける）
class Match
  # カードやルールの数値（config/cards.yml）。起動時に1回だけ読む
  CONFIG = LifeGamble::Config.load
  # メモリを使いすぎないよう、これを超えたら古い対戦から捨てる
  MAX_MATCHES = 200
  # 合言葉の長さの上限
  PASSPHRASE_MAX_LENGTH = 20
  # この時間だれも操作しなかった部屋は放置されたとみなし、同じ合言葉で新しい部屋を作れるようにする
  ROOM_IDLE_LIMIT = 30 * 60

  # 合言葉の部屋に入れなかったとき
  class RoomError < StandardError; end

  @store = {}
  @rooms = {} # 合言葉 => その合言葉の部屋（Match）
  @lock = Mutex.new

  class << self
    # 新しい対戦を作って保存する（先攻がCPUのときは、このあと act! で進める）
    def start(mode:, names:)
      save(new(mode: mode, names: names))
    end

    # 合言葉の部屋に入る。部屋がなければ作って相手を待つ。
    # 入った部屋と、自分の座席の合鍵を返す [match, seat_token]
    #   rejoin_id: このブラウザで今入っている対戦のID（自分が作った部屋に入り直すときに使う）
    def enter_room(passphrase:, name:, rejoin_id: nil)
      key = normalize_passphrase(passphrase)
      raise RoomError, "合言葉を入力してください" if key.empty?
      raise RoomError, "合言葉は#{PASSPHRASE_MAX_LENGTH}文字以内にしてください" if key.length > PASSPHRASE_MAX_LENGTH

      synchronize do
        room = @rooms[key]
        room = nil if room && (!@store.key?(room.id) || room.closed?)

        if room.nil?
          room = save(new(mode: :online, names: [ name ], passphrase: key))
          @rooms[key] = room
          [ room, room.seat_token(0) ]
        elsif room.id == rejoin_id
          [ room, nil ] # 自分の部屋。合鍵はすでに持っている
        elsif room.waiting?
          room.join!(name)
          [ room, room.seat_token(1) ]
        else
          raise RoomError, "その合言葉の部屋はすでに対戦中です。別の合言葉にしてください"
        end
      end
    end

    # 相手が来る前に部屋を閉じる
    def close_room(match)
      synchronize do
        @rooms.delete(match.passphrase) if @rooms[match.passphrase].equal?(match)
        @store.delete(match.id)
      end
    end

    def find(id)
      return nil if id.blank?

      synchronize { @store[id] }
    end

    # 全角・半角や大文字・小文字の違いは同じ合言葉として扱う
    def normalize_passphrase(raw)
      raw.to_s.unicode_normalize(:nfkc).strip.downcase
    end

    # 同じ対戦を同時に操作して状態が壊れないよう、操作はこの中で行う
    def synchronize(&block)
      @lock.owned? ? block.call : @lock.synchronize(&block)
    end

    private

    def save(match)
      synchronize do
        @store[match.id] = match
        @store.shift while @store.size > MAX_MATCHES
        @rooms.delete_if { |_, room| !@store.key?(room.id) }
      end
      match
    end
  end

  attr_reader :id, :game, :mode, :passphrase, :version
  attr_accessor :handoff

  def initialize(mode:, names:, passphrase: nil)
    @id = SecureRandom.hex(16)
    @mode = mode
    @names = names
    @passphrase = passphrase
    @ai = LifeGamble::CpuAI.new
    @handoff = pvp? # 2人対戦は最初から交代画面を出す
    @version = 0
    @touched_at = now
    @replays = {}

    if online?
      @seat_tokens = [ SecureRandom.hex(16), SecureRandom.hex(16) ]
    else
      start_game!
    end
  end

  def cpu? = mode == :cpu
  def pvp? = mode == :pvp
  def online? = mode == :online

  # オンライン対戦で、相手が来るのを待っているところ
  def waiting? = game.nil?
  def over? = !waiting? && game.over?
  # 「続きから遊ぶ」を出すか
  def in_progress? = !over?

  # 合言葉の部屋として使い終わったか（終わった対戦・放置された部屋は、同じ合言葉で作り直せる）
  def closed? = over? || now - @touched_at > ROOM_IDLE_LIMIT

  def seat_token(seat) = @seat_tokens&.fetch(seat)

  # 合鍵から座席（0 か 1）を調べる。合わなければ nil
  def seat_of(token)
    return nil if token.blank? || @seat_tokens.nil?

    @seat_tokens.index { |t| ActiveSupport::SecurityUtils.secure_compare(t, token.to_s) }
  end

  # 2人目が部屋に入って対戦を始める
  def join!(name)
    self.class.synchronize do
      @names = [ @names.first, name ]
      start_game!
      changed!
    end
  end

  # CPUの番が続く間、CPUに操作させる
  def run_cpu!
    @ai.play_turn(game) while !game.over? && game.current_player.cpu?
  end

  # プレイヤーの操作を実行し、CPUを動かす。2人対戦で手番が変わったら交代画面を出す。
  #
  # ターンが終わった（またはゲームが終わった）ときは、画面で結果を順番に再生できるよう
  # 操作する前の状態 { "from" => ログの位置, "lp" => [両者のLP] } を返す。それ以外は nil。
  # オンライン対戦では、相手が次に画面を開いたときにも再生できるよう取っておく。
  #   seat: オンライン対戦で操作した人の座席
  def act!(seat: nil)
    self.class.synchronize do
      before = game.current_player
      before_turn = game.turn_number
      snapshot = { "from" => game.log.size, "lp" => game.players.map(&:lp) }

      yield game if block_given?
      run_cpu!
      self.handoff = true if pvp? && !game.over? && !game.current_player.equal?(before)
      changed!

      ended = game.turn_number != before_turn || game.over?
      @replays[1 - seat] ||= snapshot if ended && online? && seat
      snapshot if ended
    end
  end

  # オンライン対戦で、相手のターンの結果のうち、まだ見ていない分を受け取る（受け取ったら消える）
  def take_replay(seat)
    self.class.synchronize { @replays.delete(seat) }
  end

  private

  def start_game!
    @game = LifeGamble::Game.new(names: @names, cpu: [ false, cpu? ], config: CONFIG)
  end

  # 状態が変わったことを記録する（オンライン対戦の相手の画面は、version が変わったら読み込み直す）
  def changed!
    @version += 1
    @touched_at = now
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
