ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # 並列実行はしない。スレッドで並列にすると SQLite のトランザクションがぶつかってエラーになり、
    # 対戦（Match）もサーバーのメモリ上で共有しているため、テスト同士が影響し合ってしまう
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
