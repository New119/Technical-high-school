require "yaml"

module LifeGamble
  # config/cards.yml を読み込んで、ゲーム中に使う数値を提供するクラス
  class Config
    DEFAULT_PATH = File.expand_path("../../config/cards.yml", __dir__)

    attr_reader :game, :main_cards, :support_cards, :ultimates

    def self.load(path = DEFAULT_PATH)
      # Windowsでも文字化けしないようにUTF-8を明示して読む
      new(YAML.safe_load(File.read(path, encoding: "UTF-8")))
    end

    def initialize(data)
      @game          = symbolize(data.fetch("game"))
      @main_cards    = symbolize(data.fetch("main_cards"))
      @support_cards = symbolize(data.fetch("support_cards"))
      @ultimates     = symbolize(data.fetch("ultimates"))
    end

    def title          = game[:title]
    def max_lp         = game[:max_lp]
    def start_mana     = game[:start_mana]
    def mana_per_turn  = game[:mana_per_turn]
    def mana_cap       = game[:mana_cap]
    def base_hand_size = game[:base_hand_size]

    def main(key)    = main_cards.fetch(key.to_sym)
    def support(key) = support_cards.fetch(key.to_sym)
    def ult(key)     = ultimates.fetch(key.to_sym)

    private

    # YAMLのキー(文字列)をシンボルに変換する（ネストも含めて）
    def symbolize(obj)
      case obj
      when Hash  then obj.to_h { |k, v| [ k.to_sym, symbolize(v) ] }
      when Array then obj.map { |v| symbolize(v) }
      else obj
      end
    end
  end
end
