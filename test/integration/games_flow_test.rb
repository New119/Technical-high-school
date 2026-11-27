require "test_helper"

class GamesFlowTest < ActionDispatch::IntegrationTest
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
