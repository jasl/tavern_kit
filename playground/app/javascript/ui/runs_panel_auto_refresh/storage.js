const STORAGE_KEY = "runsPanel.autoRefresh"

export function loadAutoRefreshPreference() {
  return localStorage.getItem(STORAGE_KEY) === "true"
}

export function saveAutoRefreshPreference(enabled) {
  localStorage.setItem(STORAGE_KEY, enabled ? "true" : "false")
}
