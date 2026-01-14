export function updateButtonUI(controller, active, rounds) {
  if (!controller.hasButtonTarget) return

  const btn = controller.buttonTarget

  if (active) {
    btn.classList.remove("btn-ghost")
    btn.classList.add("btn-success")
    btn.dataset.action = "click->auto-mode-toggle#stop"

    if (controller.hasIconTarget) {
      controller.iconTarget.classList.remove("icon-[lucide--play]", "icon-[lucide--fast-forward]")
      controller.iconTarget.classList.add("icon-[lucide--pause]")
    }

    if (controller.hasButton1Target) {
      controller.button1Target.classList.add("hidden")
    }
  } else {
    btn.classList.remove("btn-success")
    btn.classList.add("btn-ghost")
    btn.dataset.action = "click->auto-mode-toggle#start"

    if (controller.hasIconTarget) {
      controller.iconTarget.classList.remove("icon-[lucide--pause]")
      controller.iconTarget.classList.add("icon-[lucide--fast-forward]")
    }

    if (controller.hasButton1Target) {
      controller.button1Target.classList.remove("hidden")
    }
  }

  if (controller.hasCountTarget) {
    controller.countTarget.textContent = rounds
  }
}
