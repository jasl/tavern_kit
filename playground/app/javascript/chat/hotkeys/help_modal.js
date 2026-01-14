export function showHotkeysHelpModal() {
  const modal = document.getElementById("hotkeys_help_modal")
  if (modal && modal.showModal) {
    modal.showModal()
  }
}
