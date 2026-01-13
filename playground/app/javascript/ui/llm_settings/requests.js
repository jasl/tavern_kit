import { jsonRequest } from "../../request_helpers"
import { collectFormData } from "./form_data"
import { setFetchLoading, setTestLoading } from "./loading_state"
import { populateModelDatalist } from "./models"
import { displayConnectionResult, displayFetchError } from "./status"

export async function testConnection(controller) {
  if (!controller.providerIdValue) return

  setTestLoading(controller, true)

  try {
    const formData = collectFormData(controller)
    const { data: result } = await jsonRequest(`/settings/llm_providers/${controller.providerIdValue}/test`, {
      method: "POST",
      body: { llm_provider: formData }
    })

    displayConnectionResult(controller, result || { success: false, error: "Invalid response" })
  } catch (error) {
    displayConnectionResult(controller, { success: false, error: error.message })
  } finally {
    setTestLoading(controller, false)
  }
}

export async function fetchModels(controller) {
  if (!controller.providerIdValue && !controller.hasBaseUrlTarget) return

  setFetchLoading(controller, true)

  try {
    const formData = collectFormData(controller)

    if (!controller.providerIdValue) {
      displayFetchError(controller, "Save the provider first to fetch models")
      return
    }

    const { data: result } = await jsonRequest(`/settings/llm_providers/${controller.providerIdValue}/fetch_models`, {
      method: "POST",
      body: { llm_provider: formData }
    })

    if (!result) {
      displayFetchError(controller, "Invalid response")
      return
    }

    if (result.success && result.models) {
      populateModelDatalist(controller, result.models)
    } else {
      displayFetchError(controller, result.error || "Failed to fetch models")
    }
  } catch (error) {
    displayFetchError(controller, error.message)
  } finally {
    setFetchLoading(controller, false)
  }
}
