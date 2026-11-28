require "test_helper"

class MatchTest < ActiveSupport::TestCase
  def passphrase = "unit-#{SecureRandom.hex(4)}"

  test "合鍵で座席を見分け、合わない合鍵では座席がない" do
    word = passphrase
    match, token0 = Match.enter_room(passphrase: word, name: "A")
    _, token1 = Match.enter_room(passphrase: word, name: "B")
    assert_equal 0, match.seat_of(token0)
    assert_equal 1, match.seat_of(token1)
    assert_nil match.seat_of("wrong")
    assert_nil match.seat_of(nil)
  end

  test "終わった対戦の合言葉は、新しい部屋として使える" do
    word = passphrase
    match, = Match.enter_room(passphrase: word, name: "A")
    Match.enter_room(passphrase: word, name: "B")
    match.act!(seat: 0) { |g| g.players.each { |pl| pl.lp = 0 } && g.instance_variable_set(:@end_reason, "テスト") }

    again, = Match.enter_room(passphrase: word, name: "C")
    assert_not_equal match.id, again.id
    assert again.waiting?
  end

  test "長すぎる合言葉は使えない" do
    assert_raises(Match::RoomError) { Match.enter_room(passphrase: "あ" * 21, name: "A") }
  end
end
