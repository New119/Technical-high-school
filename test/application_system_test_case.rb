require "test_helper"

# Capybara 3.40 はテストの後片付けで Storage.clearDataForOrigin(origin: "*") を送るが、
# 新しい Chrome は「* is not a valid URL」で受け付けず、すべてのシステムテストがエラーになる。
# その命令だけ、Cookieを消す命令に置き換える（このアプリは Cookie のセッションしか使っていない）
module ChromeResetWorkaround
  def execute_cdp(cmd, **params)
    return super("Network.clearBrowserCookies") if cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeResetWorkaround)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
