export function collectFormData(controller) {
  const data = {}

  if (controller.hasBaseUrlTarget) {
    data.base_url = controller.baseUrlTarget.value
  }

  if (controller.hasApiKeyTarget && controller.apiKeyTarget.value) {
    data.api_key = controller.apiKeyTarget.value
  }

  if (controller.hasModelInputTarget) {
    data.model = controller.modelInputTarget.value
  }

  if (controller.hasStreamableToggleTarget) {
    data.streamable = controller.streamableToggleTarget.checked
  }

  return data
}
