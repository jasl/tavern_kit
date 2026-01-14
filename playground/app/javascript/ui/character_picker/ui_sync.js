export function updateCardIndicator(card, selected) {
  const indicator = card?.querySelector(".absolute.top-1.right-1 div")
  const icon = indicator?.querySelector("span")

  if (indicator && icon) {
    if (selected) {
      indicator.classList.remove("bg-base-300/80", "text-base-content/50")
      indicator.classList.add("bg-primary", "text-primary-content")
      icon.classList.remove("icon-[lucide--plus]")
      icon.classList.add("icon-[lucide--check]")
    } else {
      indicator.classList.remove("bg-primary", "text-primary-content")
      indicator.classList.add("bg-base-300/80", "text-base-content/50")
      icon.classList.remove("icon-[lucide--check]")
      icon.classList.add("icon-[lucide--plus]")
    }
  }
}

export function syncCheckboxes(controller) {
  controller.checkboxTargets.forEach(checkbox => {
    const characterId = parseInt(checkbox.value, 10)
    const shouldBeSelected = controller.selectedValue.includes(characterId)
    const card = checkbox.closest("[data-character-picker-target='card']")

    checkbox.checked = shouldBeSelected

    if (shouldBeSelected) {
      card?.classList.remove("border-transparent", "hover:border-base-300")
      card?.classList.add("border-primary", "bg-primary/5")
      updateCardIndicator(card, true)
    } else {
      card?.classList.remove("border-primary", "bg-primary/5")
      card?.classList.add("border-transparent", "hover:border-base-300")
      updateCardIndicator(card, false)
    }
  })
}

export function updateCounter(controller) {
  if (!controller.hasCounterTarget) return

  const count = controller.selectedValue.length
  controller.counterTarget.textContent = `${count} selected`
}

export function updateHiddenInputs(controller) {
  if (!controller.hasHiddenInputsTarget) return

  const inputs = controller.selectedValue.map(id => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = controller.fieldNameValue
    input.value = id
    return input
  })

  controller.hiddenInputsTarget.replaceChildren(...inputs)
}
