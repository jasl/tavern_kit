export function showHotkeysHelpModal() {
  const modal = document.getElementById("hotkeys-help-modal")
  if (modal && modal.showModal) {
    modal.showModal()
  }
}
