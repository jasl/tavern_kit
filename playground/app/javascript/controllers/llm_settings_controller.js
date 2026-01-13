import { Controller } from "@hotwired/stimulus"
import { jsonRequest } from "../request_helpers"

/**
 * LLM Settings Controller
 *
 * Handles interactive features for LLM provider configuration:
 * - Toggle API key visibility
 * - Test connection with AJAX
 * - Fetch available models
 */
export default class extends Controller {
  static targets = [
    "apiKey",
    "eyeIcon",
    "testButton",
    "testIcon",
    "testText",
    "fetchModelsButton",
    "fetchModelsIcon",
    "fetchModelsText",
    "modelInput",
    "modelDatalist",
    "baseUrl",
    "streamableToggle"
  ]

  static values = {
    providerId: Number
  }

  /**
   * Toggle API key field visibility
   */
  toggleApiKeyVisibility() {
    if (!this.hasApiKeyTarget) return

    const input = this.apiKeyTarget
    const isPassword = input.type === "password"

    input.type = isPassword ? "text" : "password"

    if (this.hasEyeIconTarget) {
      this.eyeIconTarget.className = isPassword
        ? "icon-[lucide--eye-off] size-5"
        : "icon-[lucide--eye] size-5"
    }
  }

  /**
   * Test connection to the LLM provider
   */
  async testConnection() {
    if (!this.providerIdValue) return

    this.setTestLoading(true)

    try {
      const formData = this.collectFormData()
      const { data: result } = await jsonRequest(`/settings/llm_providers/${this.providerIdValue}/test`, {
        method: "POST",
        body: { llm_provider: formData }
      })

      this.displayConnectionResult(result || { success: false, error: "Invalid response" })
    } catch (error) {
      this.displayConnectionResult({ success: false, error: error.message })
    } finally {
      this.setTestLoading(false)
    }
  }

  /**
   * Fetch available models from the API
   */
  async fetchModels() {
    if (!this.providerIdValue && !this.hasBaseUrlTarget) return

    this.setFetchLoading(true)

    try {
      const formData = this.collectFormData()

      // For new providers without an ID, we can't fetch models
      if (!this.providerIdValue) {
        this.displayFetchError("Save the provider first to fetch models")
        return
      }

      const { data: result } = await jsonRequest(`/settings/llm_providers/${this.providerIdValue}/fetch_models`, {
        method: "POST",
        body: { llm_provider: formData }
      })

      if (!result) {
        this.displayFetchError("Invalid response")
        return
      }

      if (result.success && result.models) {
        this.populateModelDatalist(result.models)
      } else {
        this.displayFetchError(result.error || "Failed to fetch models")
      }
    } catch (error) {
      this.displayFetchError(error.message)
    } finally {
      this.setFetchLoading(false)
    }
  }

  /**
   * Collect form data for API calls
   */
  collectFormData() {
    const data = {}

    if (this.hasBaseUrlTarget) {
      data.base_url = this.baseUrlTarget.value
    }

    if (this.hasApiKeyTarget && this.apiKeyTarget.value) {
      data.api_key = this.apiKeyTarget.value
    }

    if (this.hasModelInputTarget) {
      data.model = this.modelInputTarget.value
    }

    if (this.hasStreamableToggleTarget) {
      data.streamable = this.streamableToggleTarget.checked
    }

    return data
  }

  /**
   * Set loading state for test button
   */
  setTestLoading(loading) {
    if (this.hasTestButtonTarget) {
      this.testButtonTarget.disabled = loading
    }

    if (this.hasTestIconTarget) {
      this.testIconTarget.className = loading
        ? "icon-[lucide--loader-2] size-4 animate-spin"
        : "icon-[lucide--wifi] size-4"
    }

    if (this.hasTestTextTarget) {
      this.testTextTarget.textContent = loading ? "Testing..." : "Test Connection"
    }
  }

  /**
   * Set loading state for fetch models button
   */
  setFetchLoading(loading) {
    if (this.hasFetchModelsButtonTarget) {
      this.fetchModelsButtonTarget.disabled = loading
    }

    if (this.hasFetchModelsIconTarget) {
      this.fetchModelsIconTarget.className = loading
        ? "icon-[lucide--loader-2] size-4 animate-spin"
        : "icon-[lucide--refresh-cw] size-4"
    }

    if (this.hasFetchModelsTextTarget) {
      this.fetchModelsTextTarget.textContent = loading ? "Fetching..." : "Fetch"
    }
  }

  /**
   * Display connection test result
   */
  displayConnectionResult(result) {
    const statusContainer = document.getElementById(`connection-status-${this.providerIdValue}`)
    if (!statusContainer) return

    if (result.success) {
      const response = result.response ? `"${this.escapeHtml(result.response.substring(0, 100))}${result.response.length > 100 ? '...' : ''}"` : ''
      statusContainer.innerHTML = `
        <div class="alert alert-success py-3">
          <span class="icon-[lucide--check-circle] size-5"></span>
          <div>
            <p class="font-medium">Connection successful!</p>
            ${response ? `<p class="text-sm opacity-80">${response}</p>` : ''}
          </div>
        </div>
      `
    } else {
      statusContainer.innerHTML = `
        <div class="alert alert-error py-3">
          <span class="icon-[lucide--alert-circle] size-5"></span>
          <div>
            <p class="font-medium">Connection failed</p>
            <p class="text-sm opacity-80">${this.escapeHtml(result.error)}</p>
          </div>
        </div>
      `
    }
  }

  /**
   * Populate model datalist with fetched models
   */
  populateModelDatalist(models) {
    if (!this.hasModelDatalistTarget) return

    this.modelDatalistTarget.innerHTML = models
      .map(model => `<option value="${this.escapeHtml(model)}">`)
      .join('')

    // Focus the input to show the datalist
    if (this.hasModelInputTarget) {
      this.modelInputTarget.focus()
    }
  }

  /**
   * Display fetch models error
   */
  displayFetchError(message) {
    // Show a brief toast or alert for fetch errors
    const statusContainer = document.getElementById(`connection-status-${this.providerIdValue}`)
    if (statusContainer) {
      statusContainer.innerHTML = `
        <div class="alert alert-warning py-3">
          <span class="icon-[lucide--alert-triangle] size-5"></span>
          <div>
            <p class="font-medium">Could not fetch models</p>
            <p class="text-sm opacity-80">${this.escapeHtml(message)}</p>
          </div>
        </div>
      `
    }
  }

  /**
   * Escape HTML to prevent XSS.
   */
  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
