import { Controller } from "@hotwired/stimulus"
import { toggleApiKeyVisibility } from "../ui/llm_settings/api_key_visibility"
import { fetchModels, testConnection } from "../ui/llm_settings/requests"

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

  toggleApiKeyVisibility() {
    toggleApiKeyVisibility(this)
  }

  async testConnection() {
    await testConnection(this)
  }

  async fetchModels() {
    await fetchModels(this)
  }
}
