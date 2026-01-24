Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  namespace :schemas do
    resource :conversation_settings, only: %i[show]
  end

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

  # User registration with invite code
  get "join/:code", to: "join#show", as: :join
  post "join/:code", to: "join#create"

  namespace :settings do
    resources :characters, except: %i[new] do
      resources :embedded_lorebook_entries, controller: "characters/embedded_lorebook_entries", except: [:index, :show] do
        collection do
          patch :reorder
        end
      end
      member do
        post :duplicate
        post :lock
        post :unlock
        post :publish
        post :unpublish
      end
    end
    resources :llm_providers do
      member do
        post :set_default
        post :test
        post :fetch_models
        post :toggle
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
        post :lock
        post :unlock
        post :publish
        post :unpublish
      end
      collection do
        post :import
      end
    end
    resources :presets do
      member do
        post :duplicate
        post :set_default
        post :lock
        post :unlock
        post :publish
        post :unpublish
        get :export
      end
      collection do
        post :import
      end
    end
    resources :users, only: %i[index show] do
      member do
        post :toggle_status
        patch :update_role
      end
    end
    resources :invite_codes, only: %i[index show new create destroy] do
      member do
        post :regenerate
      end
    end
    # General settings
    get "general", to: "general#index", as: :general
    patch "general", to: "general#update"
  end

  # Character management (user-facing)
  resources :characters do
    resources :embedded_lorebook_entries, controller: "characters/embedded_lorebook_entries", except: [:index, :show] do
      collection do
        patch :reorder
      end
    end
    collection do
      get :picker  # Turbo Frame endpoint for character picker component
      get :picker_selected  # Turbo Frame endpoint for selected characters summary
    end
    member do
      get :portrait
      post :duplicate
    end
  end

  # Lorebook management (user-facing)
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

  # Presets management (user-facing)
  resources :presets do
    member do
      post :duplicate
      post :set_default
      get :export
    end
    collection do
      post :apply
      post :import
    end
  end

  # Playgrounds (solo roleplay spaces)
  resources :playgrounds, only: %i[new create show edit update destroy] do
    resources :conversations, only: %i[create]

    scope module: "playgrounds" do
      resources :memberships, only: %i[new create edit update destroy]

      # Space lorebook attachments
      resources :lorebooks, only: %i[index create destroy] do
        member do
          patch :toggle
        end
        collection do
          patch :reorder
        end
      end

      resource :auto_candidates, only: %i[create]
      resource :prompt_preview, only: %i[create]
    end
  end

  resources :conversations, only: %i[index show update] do
    member do
      post :regenerate
      post :branch
      post :generate
      post :stop
      post :clear_translations
      get :round_queue
      post :add_speaker
      patch :reorder_round_participants
      delete :remove_round_participant
      post :retry_current_speaker
      post :skip_current_speaker
      post :stop_round
      post :pause_round
      post :resume_round
      post :skip_turn
      post :toggle_auto_without_human
      post :cancel_stuck_run
      post :retry_stuck_run
      post :recover_idle
      get :export
      get :health
      get :runs
    end

    # Checkpoint creation (save conversation state without switching)
    resources :checkpoints, only: [:create], controller: "conversations/checkpoints"

    # Conversation lorebook attachments (ST: Chat Lore)
    scope module: "conversations" do
      resources :lorebooks, only: %i[index create destroy] do
        member do
          patch :toggle
        end
        collection do
          patch :reorder
        end
      end
    end

    resources :messages, only: %i[index create show edit update destroy] do
      member do
        get :inline_edit
        post :translate
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
