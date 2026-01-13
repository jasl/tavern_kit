export function toggleApiKeyVisibility(controller) {
  if (!controller.hasApiKeyTarget) return

  const input = controller.apiKeyTarget
  const isPassword = input.type === "password"

  input.type = isPassword ? "text" : "password"

  if (controller.hasEyeIconTarget) {
    controller.eyeIconTarget.className = isPassword
      ? "icon-[lucide--eye-off] size-5"
      : "icon-[lucide--eye] size-5"
  }
}
