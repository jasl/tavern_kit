import { Controller } from "@hotwired/stimulus"

/**
 * New Playground persona controller.
 *
 * Responsibilities:
 * - Enforce "either Persona text OR Persona Character" by disabling the inactive tab's fieldset.
 * - Prevent duplicate character usage within the new Space by disabling Persona Character choices
 *   that are already selected as AI participants (character_ids[]).
 * - If the user later selects an AI character that matches the currently selected Persona Character,
 *   automatically clears Persona Character selection (back to "No Character") and shows a notice.
 */
export default class extends Controller {
  static targets = [
    "personaFieldset",
    "characterFieldset",
    "personaOption",
    "personaCharacterRadio",
    "noCharacterRadio",
    "notice",
    "noticeText"
  ]

  connect() {
    this.selectedAiIds = new Set()

    this.onTabsChanged = this.onTabsChanged.bind(this)
    this.element.addEventListener("tabs:changed", this.onTabsChanged)

    this.connectCharacterPickerObserver()

    // Apply initial tab disable state after tabs controller initializes.
    requestAnimationFrame(() => {
      this.applyTabState(this.currentTabName())
      this.refreshSelectedAiIds()
    })
  }

  disconnect() {
    this.element.removeEventListener("tabs:changed", this.onTabsChanged)

    if (this.pickerObserver) {
      this.pickerObserver.disconnect()
      this.pickerObserver = null
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tabs
  // ─────────────────────────────────────────────────────────────────────────────

  onTabsChanged(event) {
    const tabName = event?.detail?.tab
    this.applyTabState(tabName)
  }

  currentTabName() {
    const active = this.element.querySelector("[data-tabs-target='tab'].tab-active")
    return active?.dataset?.tab || "persona"
  }

  applyTabState(tabName) {
    if (!this.hasPersonaFieldsetTarget || !this.hasCharacterFieldsetTarget) return

    const current = tabName || this.currentTabName()
    this.personaFieldsetTarget.disabled = current !== "persona"
    this.characterFieldsetTarget.disabled = current !== "character"
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Character picker integration (AI participant selection)
  // ─────────────────────────────────────────────────────────────────────────────

  connectCharacterPickerObserver() {
    const form = this.element.closest("form")
    if (!form) return

    const picker = form.querySelector("[data-controller~='character-picker']")
    if (!picker) return

    const hiddenInputs = picker.querySelector("[data-character-picker-target='hiddenInputs']")
    if (!hiddenInputs) return

    this.pickerHiddenInputs = hiddenInputs

    // Observe selection changes via hidden inputs that the character picker keeps in sync.
    this.pickerObserver = new MutationObserver(() => {
      this.refreshSelectedAiIds()
    })
    this.pickerObserver.observe(hiddenInputs, { childList: true, subtree: true })
  }

  refreshSelectedAiIds() {
    if (!this.pickerHiddenInputs) return

    const ids =
      Array.from(this.pickerHiddenInputs.querySelectorAll("input"))
        .map(input => parseInt(input.value, 10))
        .filter(Number.isFinite)

    this.selectedAiIds = new Set(ids)

    this.applyPersonaCharacterConstraints()
  }

  applyPersonaCharacterConstraints() {
    // Disable persona character options that are already selected as AI participants.
    this.personaOptionTargets.forEach(label => {
      const id = parseInt(label.dataset.characterId, 10)
      if (!Number.isFinite(id)) return

      const shouldDisable = this.selectedAiIds.has(id)

      const radio = label.querySelector("input[type='radio'][name='space_membership[character_id]']")
      if (radio) radio.disabled = shouldDisable

      label.classList.toggle("cursor-not-allowed", shouldDisable)
      label.classList.toggle("cursor-pointer", !shouldDisable)

      const card = label.querySelector(".card")
      if (card) card.classList.toggle("opacity-40", shouldDisable)

      const hint = label.querySelector("[data-persona-already-selected]")
      if (hint) hint.classList.toggle("hidden", !shouldDisable)
    })

    // If current persona character is now selected as an AI character, clear it.
    const selectedPersonaId = this.currentPersonaCharacterId()
    if (selectedPersonaId && this.selectedAiIds.has(selectedPersonaId)) {
      this.clearPersonaCharacterSelection()
      this.showConflictNotice()
    } else {
      this.hideConflictNotice()
    }
  }

  currentPersonaCharacterId() {
    const selected = this.personaCharacterRadioTargets.find(r => r.checked)
    if (!selected) return null

    const id = parseInt(selected.value, 10)
    return Number.isFinite(id) && id > 0 ? id : null
  }

  clearPersonaCharacterSelection() {
    if (!this.hasNoCharacterRadioTarget) return

    // Select "No Character"
    this.noCharacterRadioTarget.checked = true
  }

  showConflictNotice() {
    if (!this.hasNoticeTarget) return

    this.noticeTarget.classList.remove("hidden")
  }

  hideConflictNotice() {
    if (!this.hasNoticeTarget) return

    this.noticeTarget.classList.add("hidden")
  }
}
