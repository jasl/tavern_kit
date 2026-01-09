# frozen_string_literal: true

module Settings
  class LLMProvidersController < Settings::ApplicationController
    before_action :set_provider, only: %i[show edit update destroy set_default test fetch_models]

    # GET /settings/llm_providers
    def index
      providers = LLMProvider.order(:id)
      set_page_and_extract_portion_from providers, per_page: 20
      @default_provider = LLMProvider.get_default
    end

    # GET /settings/llm_providers/new
    def new
      @provider = LLMProvider.new(streamable: true, identification: "openai_compatible")
    end

    # GET /settings/llm_providers/:id
    def show
      @default_provider = LLMProvider.get_default
    end

    # GET /settings/llm_providers/:id/edit
    def edit
    end

    # POST /settings/llm_providers
    def create
      @provider = LLMProvider.new(provider_params)

      if @provider.save
        if params[:set_as_default] == "1"
          if @provider.disabled?
            redirect_to settings_llm_providers_path,
                        alert: t("llm_providers.set_default.disabled", default: "Cannot set a disabled provider as default. Enable it first.")
            return
          end

          LLMProvider.set_default!(@provider)
        end

        redirect_to settings_llm_providers_path, notice: t("llm_providers.create.success")
      else
        flash.now[:alert] = @provider.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /settings/llm_providers/:id
    def update
      # Extract streamable before compact_blank since "0" is considered blank
      streamable_value = provider_params[:streamable]

      # Build update params, excluding streamable from compact_blank
      update_params = provider_params.except(:streamable).to_h.compact_blank

      # Always include streamable if it was submitted
      update_params[:streamable] = streamable_value if provider_params.key?(:streamable)

      if @provider.update(update_params)
        if params[:set_as_default] == "1"
          if @provider.disabled?
            redirect_to settings_llm_providers_path,
                        alert: t("llm_providers.set_default.disabled", default: "Cannot set a disabled provider as default. Enable it first.")
            return
          end

          LLMProvider.set_default!(@provider)
        end
        redirect_to settings_llm_providers_path, notice: t("llm_providers.update.success")
      else
        flash.now[:alert] = @provider.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /settings/llm_providers/:id
    def destroy
      # Check if this is the default provider
      default_provider = LLMProvider.get_default
      if default_provider && @provider.id == default_provider.id
        redirect_to settings_llm_providers_path, alert: t("llm_providers.destroy.cannot_delete_default")
        return
      end

      @provider.destroy!
      redirect_to settings_llm_providers_path, notice: t("llm_providers.destroy.success")
    end

    # POST /settings/llm_providers/:id/set_default
    def set_default
      if @provider.disabled?
        redirect_to settings_llm_providers_path,
                    alert: t("llm_providers.set_default.disabled", default: "Cannot set a disabled provider as default. Enable it first.")
        return
      end

      LLMProvider.set_default!(@provider)
      redirect_to settings_llm_providers_path, notice: t("llm_providers.set_default.success", name: @provider.name)
    end

    # POST /settings/llm_providers/:id/test
    def test
      # Use form values if provided, otherwise fall back to database
      test_base_url = provider_params[:base_url].presence || @provider.base_url
      test_api_key = provider_params[:api_key].presence || @provider.api_key
      test_model = provider_params[:model].presence || @provider.model
      test_streamable = if provider_params.key?(:streamable)
                          provider_params[:streamable] == "true" || provider_params[:streamable] == "1"
      else
                          @provider.streamable?
      end

      # Model is required for testing
      if test_model.blank?
        result = { success: false, error: t("llm_providers.test.model_required") }
      else
        result = LLMClient.test_connection_with(
          base_url: test_base_url,
          api_key: test_api_key,
          model: test_model,
          streamable: test_streamable
        )

        # Update last_tested_at on successful test
        @provider.update_column(:last_tested_at, Time.current) if result[:success]
      end

      respond_to do |format|
        format.json { render json: result }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "connection-status-#{@provider.id}",
            partial: "settings/llm_providers/connection_status",
            locals: { result: result, provider: @provider }
          )
        end
      end
    end

    # POST /settings/llm_providers/:id/fetch_models
    def fetch_models
      # Use form values if provided, otherwise fall back to database
      test_base_url = provider_params[:base_url].presence || @provider.base_url
      test_api_key = provider_params[:api_key].presence || @provider.api_key

      result = LLMClient.fetch_models_with(
        base_url: test_base_url,
        api_key: test_api_key
      )

      respond_to do |format|
        format.json do
          if result[:success]
            render json: { success: true, models: result[:models] || [] }
          else
            render json: { success: false, error: result[:error] }
          end
        end
      end
    end

    private

    def set_provider
      @provider = LLMProvider.find(params[:id])
    end

    def provider_params
      params.fetch(:llm_provider, {}).permit(:name, :identification, :base_url, :api_key, :model, :streamable, :supports_logprobs, :disabled)
    end
  end
end
