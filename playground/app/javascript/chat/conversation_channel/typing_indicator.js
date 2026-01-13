export function showTypingIndicator(controller, data) {
  const {
    name = "AI",
    space_membership_id: spaceMembershipId,
    avatar_url: avatarUrl
  } = data

  controller.currentSpaceMembershipId = spaceMembershipId
  controller.lastChunkAt = Date.now()

  if (controller.hasTypingNameTarget) {
    controller.typingNameTarget.textContent = name
  }

  if (controller.hasTypingContentTarget) {
    controller.typingContentTarget.textContent = ""
  }

  if (controller.hasTypingIndicatorTarget) {
    controller.typingIndicatorTarget.classList.remove("hidden")
  }

  if (controller.hasTypingAvatarImgTarget && avatarUrl) {
    controller.typingAvatarImgTarget.src = avatarUrl
    controller.typingAvatarImgTarget.alt = name
  }

  hideStuckWarning(controller)
  resetTypingTimeout(controller)
  startStuckDetection(controller)
  scrollToTypingIndicator(controller)
}

export function hideTypingIndicator(controller, participantId = null) {
  if (participantId && controller.currentSpaceMembershipId && participantId !== controller.currentSpaceMembershipId) {
    return
  }

  if (controller.hasTypingIndicatorTarget) {
    controller.typingIndicatorTarget.classList.add("hidden")
  }

  if (controller.hasTypingContentTarget) {
    controller.typingContentTarget.textContent = ""
  }

  controller.currentSpaceMembershipId = null
  controller.lastChunkAt = null
  clearTypingTimeout(controller)
  clearStuckTimeout(controller)
  hideStuckWarning(controller)
}

export function updateTypingContent(controller, content, participantId = null) {
  if (participantId && controller.currentSpaceMembershipId && participantId !== controller.currentSpaceMembershipId) {
    return
  }

  if (controller.hasTypingContentTarget && typeof content === "string") {
    controller.typingContentTarget.textContent = content
  }

  controller.lastChunkAt = Date.now()
  hideStuckWarning(controller)
  startStuckDetection(controller)

  resetTypingTimeout(controller)
  scrollToTypingIndicator(controller)
}

export function handleStreamComplete(controller, participantId = null) {
  setTimeout(() => {
    hideTypingIndicator(controller, participantId)
  }, 100)
}

export function startStuckDetection(controller) {
  clearStuckTimeout(controller)
  controller.stuckTimeoutId = setTimeout(() => {
    showStuckWarning(controller)
  }, controller.stuckThresholdValue)
}

export function clearStuckTimeout(controller) {
  if (controller.stuckTimeoutId) {
    clearTimeout(controller.stuckTimeoutId)
    controller.stuckTimeoutId = null
  }
}

export function showStuckWarning(controller) {
  if (controller.hasStuckWarningTarget) {
    controller.stuckWarningTarget.classList.remove("hidden")
  }
}

export function hideStuckWarning(controller) {
  if (controller.hasStuckWarningTarget) {
    controller.stuckWarningTarget.classList.add("hidden")
  }
}

export function resetTypingTimeout(controller) {
  clearTypingTimeout(controller)
  controller.timeoutId = setTimeout(() => {
    hideTypingIndicator(controller)
  }, controller.timeoutValue)
}

export function clearTypingTimeout(controller) {
  if (controller.timeoutId) {
    clearTimeout(controller.timeoutId)
    controller.timeoutId = null
  }
}

export function scrollToTypingIndicator(controller) {
  const messagesContainer = controller.element.closest("[data-chat-scroll-target='messages']")
    || document.querySelector("[data-chat-scroll-target='messages']")

  if (messagesContainer) {
    requestAnimationFrame(() => {
      messagesContainer.scrollTo({
        top: messagesContainer.scrollHeight,
        behavior: "smooth"
      })
    })
  }
}
