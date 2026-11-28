require "test_helper"

class OnlineGamesTest < ActionDispatch::IntegrationTest
  # テストごとに別の合言葉を使う（部屋はサーバーのメモリに残るため）
  def passphrase = "test-#{SecureRandom.hex(4)}"

  def enter(session, name, word)
    session.post room_game_path, params: { name: name, passphrase: word }
    session.follow_redirect!
  end

  def match_of(session) = Match.find(session.session[:match_id])

  # 2人が同じ合言葉で入った状態にする [先攻のセッション, 後攻のセッション]
  def start_online
    word = passphrase
    alice = open_session
    bob = open_session
    enter(alice, "アリス", word)
    enter(bob, "ボブ", word)
    game = match_of(alice).game
    game.current_player.name == "アリス" ? [ alice, bob ] : [ bob, alice ]
  end

  test "先に入った人は相手を待ち、同じ合言葉で2人目が入ると対戦が始まる" do
    word = passphrase
    alice = open_session
    enter(alice, "アリス", word)
    assert_includes alice.response.body, "相手を待っています"
    assert_includes alice.response.body, word
    alice.get status_game_path
    version = alice.response.parsed_body["version"]

    bob = open_session
    enter(bob, "ボブ", word)
    assert_includes bob.response.body, "アリス"
    assert_equal alice.session[:match_id], bob.session[:match_id]

    alice.get status_game_path
    assert_operator alice.response.parsed_body["version"], :>, version, "相手が来たら version が変わる"
    alice.get game_path
    assert_not_includes alice.response.body, "相手を待っています"
    assert_not_includes alice.response.body, "の番です", "オンライン対戦では交代画面を出さない"
  end

  test "合言葉は全角・半角や大文字・小文字の違いを気にしない" do
    alice = open_session
    bob = open_session
    enter(alice, "アリス", "ＡＢＣ１２３")
    enter(bob, "ボブ", " abc123 ")
    assert_equal alice.session[:match_id], bob.session[:match_id]
  end

  test "対戦中の部屋には3人目は入れない" do
    first, = start_online
    carol = open_session
    carol.post room_game_path, params: { name: "キャロル", passphrase: match_of(first).passphrase }
    carol.follow_redirect!
    assert_includes carol.response.body, "すでに対戦中です"
  end

  test "自分の部屋の合言葉を入れ直しても、自分の部屋に戻る" do
    word = passphrase
    alice = open_session
    enter(alice, "アリス", word)
    enter(alice, "アリス", word)
    assert_includes alice.response.body, "相手を待っています"
  end

  test "相手の番には操作できず、自分の番だけ操作できる" do
    first, second = start_online
    first.get game_path
    assert_includes first.response.body, "手札（サポートカード）"
    second.get game_path
    assert_not_includes second.response.body, "手札（サポートカード）"
    assert_includes second.response.body, "が考えています"

    second.post main_game_path, params: { card: "small" }
    second.follow_redirect!
    assert_includes second.response.body, "相手の番です"
    assert_equal 1, match_of(first).game.turn_number, "相手の操作は無視される"

    first.post main_game_path, params: { card: "small" }
    first.follow_redirect!
    assert_includes first.response.body, "data-game-replay-value", "自分のターンの結果を再生する"

    # 相手の画面にも、ターンの結果が1回だけ再生される
    second.get game_path
    assert_includes second.response.body, "data-game-replay-value"
    second.get game_path
    assert_not_includes second.response.body, "data-game-replay-value"

    unless match_of(first).game.over?
      assert_includes second.response.body, "手札（サポートカード）", "相手がターンを終えたら自分の番"
    end
  end

  test "相手を待つのをやめると、同じ合言葉で新しい部屋が作られる" do
    word = passphrase
    alice = open_session
    enter(alice, "アリス", word)
    alice.post leave_game_path
    alice.follow_redirect!
    assert_nil alice.session[:match_id]

    bob = open_session
    enter(bob, "ボブ", word)
    assert_includes bob.response.body, "相手を待っています"
  end

  test "合言葉が空なら部屋に入れない" do
    post room_game_path, params: { name: "アリス", passphrase: "  " }
    follow_redirect!
    assert_includes response.body, "合言葉を入力してください"
  end
end
