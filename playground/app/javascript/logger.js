/* eslint-disable no-console */

const DEBUG_STORAGE_KEY = "debug"

function debugEnabled() {
  try {
    return window.localStorage.getItem(DEBUG_STORAGE_KEY) === "1"
  } catch {
    return false
  }
}

const logger = {
  debug: (...args) => {
    if (debugEnabled()) console.debug(...args)
  },
  info: (...args) => {
    if (debugEnabled()) console.info(...args)
  },
  warn: (...args) => console.warn(...args),
  error: (...args) => console.error(...args)
}

export default logger

