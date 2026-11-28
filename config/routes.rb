Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # タイトル画面とルール説明
  root "home#index"
  get "rules" => "home#rules"

  # 対戦画面（1人1つの対戦なので単数形リソース）
  resource :game, only: %i[show create] do
    post :handoff                    # 2人対戦：画面を渡したあとに押す
    post :support                    # サポートカードを使う
    post :ult                        # ウルトを使う
    post :main, action: :play_main   # メインカードを使ってターン終了
    post :pass                       # メインカード切れのときのターン終了
    post :room                       # オンライン対戦：合言葉の部屋に入る（なければ作る）
    post :leave                      # オンライン対戦：相手を待つのをやめる
    get :status                      # オンライン対戦：相手が操作したかを調べる
  end
end
