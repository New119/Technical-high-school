require "application_system_test_case"

# 直前のターンを再生している間は、マウスだけでなくキーボード（Tab→Enter）でも操作できないこと
class ReplayLockTest < ApplicationSystemTestCase
  CONTROLS = "[data-game-target=controls]".freeze

  teardown do
    # 「視差効果を減らす」のエミュレーションを元に戻す（ブラウザは次のテストでも使い回される）
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "再生中はTabで操作エリアに入れず、スキップ（キーボード）すると操作できる" do
    play_one_turn

    assert controls_inert?, "再生中は inert が付いている"
    # Tab でページ全体を何周しても、操作エリアのボタン（Enter で押せてしまう）にフォーカスが入らないこと
    focusable = page.evaluate_script("document.querySelectorAll('a[href], button, input, summary').length")
    (focusable * 2 + 2).times do
      send_keys_to_focused(:tab)
      assert_not focus_state["in_controls"], "再生中に操作エリアへフォーカスが入った"
    end

    # 「スキップ」ボタンまで Tab で進む
    tab_until { |el| el[:focused_skip] }

    # Enter でスキップ → 操作エリアが使えるようになる
    send_keys_to_focused(:enter)
    assert_no_selector ".replay-bar"
    assert_not controls_inert?, "スキップしたら inert が外れる"

    # 今度は Tab で「準備OK」に届き、Enter で押せる
    tab_until(allow_controls: true) { |el| el[:in_controls] }
    send_keys_to_focused(:enter)
    assert_text "手札（サポートカード）"
  end

  test "再生が最後まで終わると、操作エリアの inert が外れる" do
    play_one_turn
    assert controls_inert?

    using_wait_time(30) { assert_no_selector ".replay-bar" }
    assert_not controls_inert?
  end

  test "「視差効果を減らす」設定では再生せず、すぐ操作できる" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    play_one_turn

    assert_no_selector ".replay-bar"
    assert_not controls_inert?
  end

  private

  # 2人対戦を始めて先攻が「小」を使い、交代画面（直前のターンの再生つき）を出す。
  # 小の自爆（4%）で対戦が終わってしまったら、始めからやり直す
  def play_one_turn
    5.times do
      visit root_path
      choose "2人で対戦（1台で交代）"
      fill_in "プレイヤー1の名前", with: "A"
      fill_in "プレイヤー2の名前（CPU対戦では「CPU」）", with: "B"
      click_on "ゲーム開始"
      click_on "準備OK（手札を見る）"
      find(".main-card.small button").click
      # 「直前の出来事を見る」は交代画面にだけある（自爆したときの結果画面にはない）
      return if has_text?("直前の出来事を見る") && has_selector?(CONTROLS, visible: :all, wait: 0)
    end
    flunk "交代画面まで進めなかった"
  end

  def controls_inert?
    page.evaluate_script("document.querySelector('#{CONTROLS}').inert")
  end

  def focus_state
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.activeElement
        return {
          in_controls: !!el?.closest("#{CONTROLS}"),
          focused_skip: !!el?.matches("[data-action='game#skip']")
        }
      })()
    JS
  end

  # Tab を押し続け、ブロックが true を返す要素にフォーカスが来たら止まる
  def tab_until(allow_controls: false, max: 40)
    max.times do
      send_keys_to_focused(:tab)
      state = focus_state.transform_keys(&:to_sym)
      assert_not state[:in_controls], "再生中に操作エリアへフォーカスが入った" unless allow_controls
      return if yield(state)
    end
    flunk "目的の要素まで Tab で届かなかった"
  end

  def send_keys_to_focused(key)
    page.driver.browser.action.send_keys(key).perform
  end
end
