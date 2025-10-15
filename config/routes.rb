Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/media-stream"

  namespace :api, defaults: { format: :json } do
    namespace :v1, defaults: { format: :json } do
      root "home#index"

      post "/incoming-call", to: "calls#incoming"
      get "/download-recording/:call_sid", to: "calls#download_recording"

      post "transcribe" => "home#transcribe"
      post "file_transcribe" => "home#file_transcribe"
      post "routine_completions" => "home#routine_completions"
      post "agent_scraping" => "home#agent_scraping"
      post "data_agent_scraping" => "home#data_agent_scraping"
      post "completion" => "home#completion"
      post "video_metadata" => "home#youtube_metadata"

      post "meet_summary" => "actas#meet_summary"
      post "convert_to_json" => "home#convert_to_json"
      # get 'public_calendar_ics' => 'home#public_calendar_ics'
      get "public_calendar_ic" => "home#public_calendar_ic"

      post "data_format" => "home#data_format"
      get "historical" => "finance#historical" # TODO: ver opcion POST
      get "symbol_search" => "finance#symbol_search" # TODO: ver opcion POST
      get "comprehensive" => "finance#comprehensive" # TODO: ver opcion POST
      get "rss" => "finance#rss" # TODO: ver opcion POST
      post "query_type" => "finance#query_type"
      post "generate_signal" => "finance#generate_signal"
      post "anality" => "finance#anality"

      resources :shopify do
        collection do
          post :create_product
          post :migrar_productos
        end
      end
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
