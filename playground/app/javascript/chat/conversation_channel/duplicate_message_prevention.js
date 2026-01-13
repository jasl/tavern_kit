export function setupDuplicateMessagePrevention(controller) {
  controller.handleTurboStreamRender = (event) => {
    const fallbackToDefaultActions = event.detail.render

    event.detail.render = (streamElement) => {
      const action = streamElement.getAttribute("action")

      if (action === "append") {
        const template = streamElement.querySelector("template")
        if (template) {
          const content = template.content.firstElementChild
          if (content && content.id && content.id.startsWith("message_")) {
            const existingElement = document.getElementById(content.id)
            if (existingElement) return
          }
        }
      }

      fallbackToDefaultActions(streamElement)
    }
  }

  document.addEventListener("turbo:before-stream-render", controller.handleTurboStreamRender)
}

export function teardownDuplicateMessagePrevention(controller) {
  if (controller.handleTurboStreamRender) {
    document.removeEventListener("turbo:before-stream-render", controller.handleTurboStreamRender)
    controller.handleTurboStreamRender = null
  }
}
