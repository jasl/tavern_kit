import { regenerateTailAssistant, stopGeneration, swipeTailAssistant } from "./actions"
import { cancelAnyOpenEdit, editLastOwnMessage, editLastUserMessage, shouldHandleEditHotkey } from "./edit"
import { showHotkeysHelpModal } from "./help_modal"
import { canRegenerateTail, canSwipeTail } from "./tail"

function isActiveElementInOtherTextInput(controller) {
  const activeElement = document.activeElement
  const isInInput = activeElement && (
    activeElement.tagName === "INPUT" ||
    (activeElement.tagName === "TEXTAREA" && activeElement !== controller.textareaTarget)
  )
  return !!isInInput
}

function isActiveElementInAnyInput() {
  const activeElement = document.activeElement
  const isInInput = activeElement && (
    activeElement.tagName === "INPUT" ||
    activeElement.tagName === "TEXTAREA" ||
    activeElement.isContentEditable
  )
  return !!isInInput
}

export function handleKeydown(controller, event) {
  // IME protection: don't intercept during composition (e.g., CJK input)
  if (event.isComposing) return

  // Escape: Cancel any open inline edit, or stop generation
  if (event.key === "Escape") {
    if (cancelAnyOpenEdit()) {
      event.preventDefault()
      return
    }
    // No inline edit open - stop generation
    if (controller.hasStopUrlValue) {
      event.preventDefault()
      stopGeneration(controller)
      return
    }
  }

  // Ctrl+Enter: Regenerate tail AI response (only if tail is assistant)
  if (event.key === "Enter" && event.ctrlKey && !event.shiftKey && !event.altKey && !event.metaKey) {
    if (canRegenerateTail(controller)) {
      event.preventDefault()
      regenerateTailAssistant(controller)
    }
    return
  }

  // Ctrl+ArrowUp: Edit last user-role message sent by current user
  if (event.key === "ArrowUp" && event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey) {
    if (shouldHandleEditHotkey(controller)) {
      event.preventDefault()
      editLastUserMessage(controller)
      return
    }
  }

  // ArrowUp (no modifiers): Edit last message sent by current user
  if (event.key === "ArrowUp" && !event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey) {
    if (shouldHandleEditHotkey(controller)) {
      event.preventDefault()
      editLastOwnMessage(controller)
      return
    }
  }

  // ArrowLeft/ArrowRight: Swipe through versions (only if tail is assistant with swipes)
  if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
    // Don't intercept if user is in an input field (other than our textarea)
    if (isActiveElementInOtherTextInput(controller)) return

    // Disable swipe hotkeys when textarea has content
    if (controller.hasTextareaTarget && controller.textareaTarget.value.trim().length > 0) {
      return
    }

    // Don't intercept if modifier keys are pressed
    if (event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) return

    // Only preventDefault if tail is assistant with swipes
    if (canSwipeTail(controller)) {
      event.preventDefault()
      const direction = event.key === "ArrowLeft" ? "left" : "right"
      swipeTailAssistant(controller, direction)
    }
  }

  // ?: Show hotkeys help modal (when not in input field)
  if (event.key === "?") {
    // Don't intercept if user is in any input field
    if (isActiveElementInAnyInput()) return

    event.preventDefault()
    showHotkeysHelpModal()
  }

  // Note: [ and ] sidebar toggles are handled by sidebar_controller.js
}
