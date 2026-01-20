export function updateButtonUI(controller, active, rounds) {
  if (!controller.hasButtonTarget) return

  const btn = controller.buttonTarget

  if (active) {
    btn.classList.remove("btn-ghost")
    btn.classList.add("btn-success")

    if (controller.hasIconTarget) {
      controller.iconTarget.classList.remove("icon-[lucide--play]", "icon-[lucide--fast-forward]")
      controller.iconTarget.classList.add("icon-[lucide--pause]")
    }
  } else {
    btn.classList.remove("btn-success")
    btn.classList.add("btn-ghost")

    if (controller.hasIconTarget) {
      controller.iconTarget.classList.remove("icon-[lucide--pause]")
      controller.iconTarget.classList.add("icon-[lucide--fast-forward]")
    }
  }

  if (controller.hasCountTarget) {
    controller.countTarget.textContent = rounds
  }
}
