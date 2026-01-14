import logger from "../../logger"
import { jsonPatch } from "../../request_helpers"
import { setSavedAt, setStatus } from "./status"

export async function sendUpdate(controller, settings) {
  setStatus(controller, "saving")

  try {
    const { response, data: result } = await jsonPatch(controller.urlValue, {
      body: { authors_note_settings: settings }
    })

    if (!response.ok || !result) {
      setStatus(controller, "error")
      logger.error("Failed to save: invalid response")
      return
    }

    if (result.ok) {
      setStatus(controller, "saved")
      setSavedAt(controller, result.saved_at)
    } else {
      setStatus(controller, "error")
      logger.error("Failed to save:", result.errors)
    }
  } catch (error) {
    setStatus(controller, "error")
    logger.error("Save error:", error)
  }
}

