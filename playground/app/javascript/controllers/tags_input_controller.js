import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

/**
 * Tags input controller for managing array values as tag chips.
 *
 * @example HTML structure
 *   <div data-controller="tags-input" data-tags-input-max-items-value="16">
 *     <div class="flex flex-wrap gap-1">
 *       <span data-tags-input-target="tag">Tag 1 <button data-action="tags-input#remove">&times;</button></span>
 *       <input data-tags-input-target="input" data-action="keydown->tags-input#handleKeydown">
 *     </div>
 *     <input type="hidden" data-tags-input-target="hidden" value='["Tag 1"]'>
 *   </div>
 */
export default class extends Controller {
  static targets = ["input", "hidden", "tag"]
  static values = {
    maxItems: { type: Number, default: 16 }
  }

  get tags() {
    try {
      return JSON.parse(this.hiddenTarget.value || "[]")
    } catch {
      return []
    }
  }

  set tags(value) {
    this.hiddenTarget.value = JSON.stringify(value)
    // Trigger change event for settings-form controller
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  handleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.add()
    } else if (event.key === "Backspace" && event.currentTarget.value === "") {
      this.removeLast()
    }
  }

  add() {
    const input = this.inputTarget
    const value = input.value.trim()

    if (!value) return

    const currentTags = this.tags

    // Check max items
    if (currentTags.length >= this.maxItemsValue) {
      return
    }

    // Check for duplicates
    if (currentTags.includes(value)) {
      input.value = ""
      return
    }

    // Add new tag
    currentTags.push(value)
    this.tags = currentTags

    // Create tag element
    this.createTagElement(value)

    // Clear input
    input.value = ""
  }

  remove(event) {
    const tagEl = event.currentTarget.closest("[data-tags-input-target='tag']")
    const tagText = tagEl.textContent.replace("×", "").trim()

    // Remove from array
    const currentTags = this.tags.filter(t => t !== tagText)
    this.tags = currentTags

    // Remove element
    tagEl.remove()
  }

  removeLast() {
    if (this.tagTargets.length === 0) return

    const lastTag = this.tagTargets[this.tagTargets.length - 1]
    const tagText = lastTag.textContent.replace("×", "").trim()

    // Remove from array
    const currentTags = this.tags.filter(t => t !== tagText)
    this.tags = currentTags

    // Remove element
    lastTag.remove()
  }

  createTagElement(value) {
    const template = document.getElementById("tag_chip_template")
    if (!template) {
      logger.warn("[tags-input] Tag template not found")
      return
    }

    const tag = template.content.cloneNode(true).firstElementChild
    // Set the tag text using textContent (auto-escapes, prevents XSS)
    tag.querySelector("[data-tag-text]").textContent = value

    const container = this.inputTarget.parentElement
    container.insertBefore(tag, this.inputTarget)
  }
}
