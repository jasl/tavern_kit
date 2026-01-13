import logger from "../../logger"
import { turboRequest } from "../../request_helpers"
import { showLoadingIndicator, hideLoadingIndicator } from "./indicators"
import { getFirstMessageElement } from "./messages_dom"

const HISTORY_PAGE_SIZE = 20

export function setupIntersectionObserver(controller) {
  if (!controller.hasLoadMoreTarget) return () => {}

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && !controller.loadingValue && controller.hasMoreValue) {
          loadMoreMessages(controller)
        }
      })
    },
    {
      root: controller.hasMessagesTarget ? controller.messagesTarget : null,
      rootMargin: "100px 0px 0px 0px",
      threshold: 0
    }
  )

  observer.observe(controller.loadMoreTarget)

  return () => observer.disconnect()
}

async function loadMoreMessages(controller) {
  if (controller.loadingValue || !controller.hasMoreValue || !controller.loadMoreUrlValue) return

  controller.loadingValue = true
  showLoadingIndicator(controller)

  const firstMessage = getFirstMessageElement(controller)
  if (!firstMessage) {
    controller.loadingValue = false
    controller.hasMoreValue = false
    hideLoadingIndicator(controller)
    return
  }

  const messageId = firstMessage.id.replace("message_", "")
  const url = `${controller.loadMoreUrlValue}?before=${messageId}`

  const scrollHeightBefore = controller.messagesTarget.scrollHeight

  try {
    const { response, renderedTurboStream } = await turboRequest(url, {
      accept: "text/html",
      headers: { "X-Requested-With": "XMLHttpRequest" }
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    if (renderedTurboStream) return

    const html = await response.text()

    const parser = new DOMParser()
    const doc = parser.parseFromString(html, "text/html")
    const newMessages = doc.querySelectorAll(".mes[id^='message_']")

    if (newMessages.length === 0) {
      controller.hasMoreValue = false
      return
    }

    const fragment = document.createDocumentFragment()
    newMessages.forEach((msg) => fragment.appendChild(msg.cloneNode(true)))
    controller.listTarget.insertBefore(fragment, controller.listTarget.firstChild)

    const scrollHeightAfter = controller.messagesTarget.scrollHeight
    const heightDiff = scrollHeightAfter - scrollHeightBefore
    controller.messagesTarget.scrollTop += heightDiff

    if (newMessages.length < HISTORY_PAGE_SIZE) {
      controller.hasMoreValue = false
    }
  } catch (error) {
    logger.error("Failed to load more messages:", error)
  } finally {
    controller.loadingValue = false
    hideLoadingIndicator(controller)
  }
}
