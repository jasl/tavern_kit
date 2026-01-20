import logger from "../../logger"

export function showTypingIndicator(controller, data) {
  const {
    name = "AI",
    space_membership_id: spaceMembershipId,
    avatar_url: avatarUrl,
    target_message_id: targetMessageId
  } = data

  controller.currentSpaceMembershipId = spaceMembershipId
  controller.lastChunkAt = Date.now()
  controller.targetMessageId = targetMessageId || null

  // If regenerating a specific message, try to show inline indicator there
  if (targetMessageId) {
    const inlineSuccess = showInlineTypingIndicator(controller, targetMessageId)
    if (inlineSuccess) {
      hideStuckWarning(controller)
      resetTypingTimeout(controller)
      startStuckDetection(controller)
      scrollToTargetMessage(controller, targetMessageId)
      return
    }
    // Inline indicator failed (DOM not found), fall back to bottom indicator
    controller.targetMessageId = null // Clear so updates go to bottom indicator
  }

  // Default: show bottom typing indicator
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
  scrollToTypingIndicator(controller, { behavior: "smooth", force: true })
}

export function hideTypingIndicator(controller, participantId = null) {
  if (participantId && controller.currentSpaceMembershipId && participantId !== controller.currentSpaceMembershipId) {
    return
  }

  // Clean up inline indicator if present
  if (controller.targetMessageId) {
    hideInlineTypingIndicator(controller.targetMessageId)
  }

  if (controller.hasTypingIndicatorTarget) {
    controller.typingIndicatorTarget.classList.add("hidden")
  }

  if (controller.hasTypingContentTarget) {
    controller.typingContentTarget.textContent = ""
  }

  controller.currentSpaceMembershipId = null
  controller.lastChunkAt = null
  controller.targetMessageId = null
  controller.lastAutoScrollAt = null
  clearTypingTimeout(controller)
  clearStuckTimeout(controller)
  hideStuckWarning(controller)
}

export function updateTypingContent(controller, content, participantId = null) {
  if (participantId && controller.currentSpaceMembershipId && participantId !== controller.currentSpaceMembershipId) {
    return
  }

  // If regenerating a specific message, update inline indicator
  if (controller.targetMessageId) {
    updateInlineTypingContent(controller.targetMessageId, content)
    controller.lastChunkAt = Date.now()
    hideStuckWarning(controller)
    startStuckDetection(controller)
    resetTypingTimeout(controller)
    // Don't scroll on every chunk for inline - only scroll once at start
    return
  }

  // Default: update bottom typing indicator
  if (controller.hasTypingContentTarget && typeof content === "string") {
    controller.typingContentTarget.textContent = content
  }

  controller.lastChunkAt = Date.now()
  hideStuckWarning(controller)
  startStuckDetection(controller)

  resetTypingTimeout(controller)
  scrollToTypingIndicator(controller, { behavior: "auto", force: false })
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

export function scrollToTypingIndicator(controller, { behavior = "smooth", force = true } = {}) {
  const messagesContainer = controller.element.closest("[data-chat-scroll-target='messages']")
    || document.querySelector("[data-chat-scroll-target='messages']")

  if (messagesContainer) {
    if (!force) {
      const distanceFromBottom =
        messagesContainer.scrollHeight - (messagesContainer.scrollTop + messagesContainer.clientHeight)

      // Only auto-scroll while the user is already following the bottom.
      if (distanceFromBottom > 80) return

      // Throttle frequent chunk updates to avoid scroll jitter.
      const now = Date.now()
      if (controller.lastAutoScrollAt && (now - controller.lastAutoScrollAt) < 150) return
      controller.lastAutoScrollAt = now
    }

    requestAnimationFrame(() => {
      messagesContainer.scrollTo({
        top: messagesContainer.scrollHeight,
        behavior
      })
    })
  }
}

// ============================================================================
// Inline Typing Indicator (for regeneration)
// ============================================================================

const INLINE_INDICATOR_ID_PREFIX = "inline-typing-"

/**
 * Show an inline typing indicator at the target message.
 * This replaces the message content with a typing indicator during regeneration.
 *
 * @param {Object} controller - The Stimulus controller
 * @param {number} messageId - The ID of the target message
 * @returns {boolean} true if inline indicator was shown, false if DOM lookup failed
 */
function showInlineTypingIndicator(controller, messageId) {
  const messageEl = document.getElementById(`message_${messageId}`)
  if (!messageEl) return false

  // Find the turbo frame containing the message content
  const contentFrame = messageEl.querySelector(`[id^="content_message_"]`)
  if (!contentFrame) return false

  const template = document.getElementById("inline_typing_indicator_template")
  if (!template) {
    logger.warn("[typing-indicator] Inline typing indicator template not found")
    return false
  }

  const indicatorId = `${INLINE_INDICATOR_ID_PREFIX}${messageId}`
  const indicator = template.content.cloneNode(true).firstElementChild
  if (!indicator) return false

  indicator.id = indicatorId

  const contentEl = indicator.querySelector("[data-inline-typing-content]")
  if (contentEl) {
    contentEl.id = `${indicatorId}-content`
  }

  // Replace content frame contents with indicator
  contentFrame.replaceChildren(indicator)

  // Add CSS to hide dots when content is present
  addInlineTypingStyles()

  return true
}

/**
 * Hide and clean up the inline typing indicator.
 */
function hideInlineTypingIndicator(messageId) {
  const indicatorId = `${INLINE_INDICATOR_ID_PREFIX}${messageId}`
  const indicator = document.getElementById(indicatorId)

  if (indicator) {
    // The Turbo Stream will replace the content frame anyway,
    // so we just need to clean up our indicator
    indicator.remove()
  }
}

/**
 * Update the content in the inline typing indicator.
 */
function updateInlineTypingContent(messageId, content) {
  const indicatorId = `${INLINE_INDICATOR_ID_PREFIX}${messageId}`
  const contentEl = document.getElementById(`${indicatorId}-content`)

  if (contentEl && typeof content === "string") {
    contentEl.textContent = content

    // Hide dots when we have content
    const indicator = document.getElementById(indicatorId)
    if (indicator) {
      const dots = indicator.querySelector("[data-inline-typing-dots]")
      if (dots) {
        dots.style.display = content ? "none" : "flex"
      }
    }
  }
}

/**
 * Scroll to bring the target message into view.
 */
function scrollToTargetMessage(controller, messageId) {
  const messageEl = document.getElementById(`message_${messageId}`)
  if (!messageEl) return

  const messagesContainer = controller.element.closest("[data-chat-scroll-target='messages']")
    || document.querySelector("[data-chat-scroll-target='messages']")

  if (messagesContainer && messageEl) {
    requestAnimationFrame(() => {
      messageEl.scrollIntoView({ behavior: "smooth", block: "center" })
    })
  }
}

/**
 * Add CSS styles for inline typing indicator (injected once).
 */
let stylesInjected = false
function addInlineTypingStyles() {
  if (stylesInjected) return
  stylesInjected = true

  const style = document.createElement("style")
  style.textContent = `
    .inline-typing-indicator {
      animation: fadeIn 0.2s ease-out;
    }
    @keyframes fadeIn {
      from { opacity: 0; }
      to { opacity: 1; }
    }
  `
  document.head.appendChild(style)
}
