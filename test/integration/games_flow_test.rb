require "test_helper"

class GamesFlowTest < ActionDispatch::IntegrationTest
  # 2人対戦を始めて、先攻プレイヤーの手札とマナを決めた状態にする（交代画面は閉じておく）
  def start_my_turn(hand:, mana:)
    post game_path, params: { mode: "pvp", name1: "A", name2: "B" }
    post handoff_game_path
    player = Match.find(session[:match_id]).game.current_player
    player.hand = hand
    player.mana = mana
  end
  test "タイトルとルールが表示される" do
    get root_path
    assert_response :success
    assert_includes response.body, "ゲーム開始"

    get rules_path
    assert_response :success
    assert_includes response.body, "自爆確率"
  end

  test "対戦が始まっていなければタイトルに戻される" do
    get game_path
    assert_redirected_to root_path
  end

  test "CPU戦を最後まで遊べる" do
    post game_path, params: { mode: "cpu", name1: "テスト" }
    assert_redirected_to game_path

    30.times do
      follow_redirect! if response.redirect?
      break if response.body.include?("同じ設定でもう一度")

      card = %w[small medium large].find { |k| response.body.include?(%(value="#{k}")) }
      if card
        post main_game_path, params: { card: card }
      else
        post pass_game_path
      end
    end

    follow_redirect! if response.redirect?
    assert_response :success
    assert_includes response.body, "同じ設定でもう一度"
  end

  test "ルール違反の操作はエラーメッセージを表示する" do
    post game_path, params: { mode: "pvp", name1: "A", name2: "B" }
    post handoff_game_path
    post pass_game_path
    follow_redirect!
    assert_includes response.body, "メインカードが残っている間は"
  end

  test "2人対戦では交代画面が出る" do
    post game_path, params: { mode: "pvp", name1: "A", name2: "B" }
    follow_redirect!
    assert_includes response.body, "の番です"

    post handoff_game_path
    follow_redirect!
    assert_includes response.body, "手札（サポートカード）"

    post main_game_path, params: { card: "small" }
    follow_redirect!
    # 小の自爆(4%)で終わることもあるので、交代画面か結果画面のどちらか
    assert(response.body.include?("の番です") || response.body.include?("同じ設定でもう一度"))
  end

  test "ターンが終わった直後の画面だけ、結果を再生するデータが入る" do
    post game_path, params: { mode: "pvp", name1: "A", name2: "B" }
    follow_redirect!
    assert_not_includes response.body, "data-game-replay-value"

    post handoff_game_path
    follow_redirect!
    assert_not_includes response.body, "data-game-replay-value", "ターンが終わっていない操作では再生しない"

    post main_game_path, params: { card: "small" }
    follow_redirect!
    assert_includes response.body, "data-game-replay-value"
    assert_includes response.body, "replay-pending"
    assert_includes response.body, "直前のターンを再生中"
    # 再生前（操作前）のLPから表示を始める
    assert_includes response.body, %(<span class="lp-value">6000</span>)

    get game_path
    assert_not_includes response.body, "data-game-replay-value", "再読み込みしたら再生しない"
  end

  test "サポートカードを使うと、お知らせと「このターンに使ったカード」に表示される" do
    start_my_turn(hand: %i[heal mana_boost], mana: 5)
    get game_path
    assert_includes response.body, "まだ使っていません"
    assert_includes response.body, "使う（💎3）"

    post support_game_path, params: { index: 0 }
    follow_redirect!
    assert_includes response.body, "「回復」を使いました（マナ -3）。効果はターン終了時に発動します"
    assert_select ".pending-card.pending-support.just-used .pending-name", "回復"
    assert_select ".card.support .btn", "使う（💎2）" # 残り2マナでマナブーストは使える
  end

  test "マナが足りないカードは、あと何マナ必要か表示する" do
    start_my_turn(hand: %i[opponent_danger], mana: 1)
    get game_path
    assert_select ".card.support .btn[disabled]", "マナ不足（あと3）"
  end

  test "ウルトはボタンから捨てるカードを選んで発動する" do
    start_my_turn(hand: %i[heal heal heal hand_up], mana: 0)
    get game_path
    assert_select "button.ult[data-ult-key=extra_turn][data-ult-need='3']"
    assert_select "button.ult[data-ult-key=full_heal][data-ult-need='4']"
    assert_select "button.ult[data-ult-key=immunity][data-ult-need=all]"
    assert_select "form#ult-form[hidden]"
    assert_select "input[type=checkbox][name='discard[]'][form=ult-form]", 4

    post ult_game_path, params: { ult: "extra_turn", discard: %w[0 1 2] }
    follow_redirect!
    assert_includes response.body, "ウルト「追加ターン」を発動しました（手札3枚を捨てた）"
    assert_select ".pending-card.pending-ult .pending-name", "ウルト：追加ターン"
    assert_select "button.ult[disabled]", 5 # 1ターン1回
  end

  test "手札が足りないウルトは理由を表示する" do
    start_my_turn(hand: %i[heal], mana: 0)
    get game_path
    assert_select "button.ult[data-ult-key=full_heal][disabled] .ult-reason", "手札が3枚足りません"
  end

  test "自爆率低下を使うと、メインカードの自爆率が変わったことを表示する" do
    start_my_turn(hand: %i[self_safety], mana: 3)
    post support_game_path, params: { index: 0 }
    follow_redirect!
    assert_select "form.main-card.large .death .rate-before", "50.0%"
    assert_select "form.main-card.large .death .rate-down", "25.0%"
  end

  test "CPU戦ではCPUのターンまでまとめて再生する" do
    post game_path, params: { mode: "cpu", name1: "テスト" }
    post main_game_path, params: { card: "small" }
    follow_redirect!
    assert_includes response.body, "data-game-replay-value"
    # 自分が自爆して終わった場合以外は、続けて動いたCPUのターンも再生対象に入る
    unless response.body.include?("テストは自爆した")
      assert_includes response.body, %(data-replay-step), "再生するログがある"
      assert_match(/CPUはメインカード「.」を使った/, response.body)
    end
  end
end
