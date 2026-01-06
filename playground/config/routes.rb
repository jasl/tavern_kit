Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  get "/schemas/settings", to: "schemas/settings#show", as: :schemas_settings

  # Portrait serving routes (Campfire pattern: relative URLs via signed IDs)
  # These serve portraits directly, avoiding Active Storage's absolute URL requirement
  scope :portraits do
    get "space_memberships/:signed_id", to: "portraits#space_membership", as: :space_membership_portrait
    get "characters/:signed_id", to: "portraits#character", as: :character_portrait
  end

  # Cache-busting portrait URL helpers (following Campfire's fresh_user_avatar pattern)
  direct :fresh_space_membership_portrait do |membership, options|
    route_for :space_membership_portrait,
              membership.signed_id(purpose: :portrait),
              v: membership.updated_at.to_fs(:number),
              **options
  end

  direct :fresh_character_portrait do |character, options|
    # Use portrait blob key if attached for guaranteed cache busting on portrait change
    cache_key = if character.portrait.attached?
                  character.portrait.blob.key
    else
                  character.updated_at.to_fs(:number)
    end
    route_for :character_portrait,
              character.signed_id(purpose: :portrait),
              v: cache_key,
              **options
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes (placeholder for Phase 4)
  # get "manifest" => "pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "pwa#service_worker", as: :pwa_service_worker

  # Root path
  root "welcome#index"

  # First run setup wizard
  resource :first_run, only: %i[show create]

  # Session management
  resource :session, only: %i[new create destroy]

  namespace :settings do
    resources :characters, except: %i[new show]
    resources :llm_providers do
      member do
        post :set_default
        post :test
        post :fetch_models
      end
    end
    resources :lorebooks do
      resources :entries, controller: "lorebooks/entries", except: [:index] do
        collection do
          patch :reorder
        end
      end
      member do
        post :duplicate
        get :export
      end
      collection do
        post :import
      end
    end
  end

  # Presets (LLM settings presets)
  resources :presets, only: %i[index create update destroy] do
    member do
      post :set_default
    end
  end
  post "presets/apply", to: "presets#apply", as: :apply_preset

  # Character management
  resources :characters, only: %i[index show] do
    member do
      get :portrait
    end
  end

  # Playgrounds (solo roleplay spaces)
  resources :playgrounds, only: %i[index new create show edit update destroy] do
    resources :space_memberships, only: %i[new create edit update destroy]
    resources :conversations, only: %i[create]

    # Space lorebook attachments
    resources :space_lorebooks, only: %i[index create destroy] do
      member do
        patch :toggle
      end
      collection do
        patch :reorder
      end
    end

    scope module: "playgrounds" do
      resource :copilot_candidates, only: %i[create]
      resource :prompt_preview, only: %i[create]
    end
  end

  resources :conversations, only: %i[show update] do
    member do
      post :regenerate
      post :branch
      post :generate
      post :stop
    end

    # Checkpoint creation (save conversation state without switching)
    resources :checkpoints, only: [:create], controller: "conversations/checkpoints"

    resources :messages, only: %i[index create show edit update destroy] do
      member do
        get :inline_edit
      end
      # Swipe navigation for AI response versions
      resource :swipe, only: [:create], controller: "conversations/messages/swipes"
      # Context visibility toggle (include/exclude from prompt)
      resource :visibility, only: [:update], controller: "conversations/messages/visibilities"
    end
  end

  # OpenAI-compatible mock LLM API for development/testing (used by LLMClient).
  if Rails.env.development? || Rails.env.test?
    namespace :mock_llm do
      namespace :v1 do
        post "chat/completions", to: "chat_completions#create"
        get "models", to: "models#index"
      end
    end
  end
end
