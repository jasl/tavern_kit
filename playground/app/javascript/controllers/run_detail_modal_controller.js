import { Controller } from "@hotwired/stimulus"

/**
 * Run Detail Modal Controller
 *
 * Handles the debug modal for displaying conversation run details.
 * Shows run metadata, error payloads, and allows copying prompt JSON.
 *
 * The modal is opened by clicking a run item in the runs panel.
 * Run data is passed via data attributes on the clicked element.
 */
export default class extends Controller {
  static targets = ["content", "copyButton"]

  // Store the current run data for copying
  currentRunData = null

  /**
   * Open the modal and populate it with run data.
   *
   * @param {Object} runData - The run data object
   */
  showRun(runData) {
    this.currentRunData = runData
    this.renderContent(runData)
    this.element.showModal()

    // Enable copy button if prompt snapshot exists
    if (this.hasCopyButtonTarget) {
      this.copyButtonTarget.disabled = !runData.prompt_snapshot
    }
  }

  /**
   * Render the run details content.
   *
   * @param {Object} data - The run data
   */
  renderContent(data) {
    if (!this.hasContentTarget) return

    const html = `
      <div class="grid grid-cols-2 gap-4">
        <!-- Status & Timing -->
        <div class="bg-base-200 rounded-lg p-3 space-y-2">
          <h4 class="font-semibold text-sm flex items-center gap-2">
            <span class="icon-[lucide--info] size-4"></span>
            Status
          </h4>
          <div class="space-y-1 text-sm">
            <div class="flex justify-between">
              <span class="text-base-content/60">Status</span>
              <span class="badge badge-sm ${this.statusBadgeClass(data.status)}">${data.status}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Kind</span>
              <span>${data.kind || '-'}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Trigger</span>
              <span>${data.trigger || '-'}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Created</span>
              <span>${this.formatTime(data.created_at)}</span>
            </div>
            ${data.started_at ? `
            <div class="flex justify-between">
              <span class="text-base-content/60">Started</span>
              <span>${this.formatTime(data.started_at)}</span>
            </div>
            ` : ''}
            ${data.finished_at ? `
            <div class="flex justify-between">
              <span class="text-base-content/60">Finished</span>
              <span>${this.formatTime(data.finished_at)}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Duration</span>
              <span>${this.calculateDuration(data.started_at, data.finished_at)}</span>
            </div>
            ` : ''}
          </div>
        </div>

        <!-- Speaker & Generation -->
        <div class="bg-base-200 rounded-lg p-3 space-y-2">
          <h4 class="font-semibold text-sm flex items-center gap-2">
            <span class="icon-[lucide--user] size-4"></span>
            Generation
          </h4>
          <div class="space-y-1 text-sm">
            <div class="flex justify-between">
              <span class="text-base-content/60">Speaker</span>
              <span>${data.speaker_name || data.speaker_membership_id || '-'}</span>
            </div>
            ${data.generation_params ? `
            <div class="flex justify-between">
              <span class="text-base-content/60">Provider</span>
              <span>${data.generation_params.provider_name || '-'}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Model</span>
              <span class="font-mono text-xs">${data.generation_params.model || '-'}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Max Tokens</span>
              <span>${data.generation_params.max_response_tokens || '-'}</span>
            </div>
            ${data.generation_params.temperature !== undefined ? `
            <div class="flex justify-between">
              <span class="text-base-content/60">Temperature</span>
              <span>${data.generation_params.temperature}</span>
            </div>
            ` : ''}
            ` : ''}
          </div>
        </div>
      </div>

      <!-- Token Usage -->
      ${data.usage ? `
      <div class="bg-base-200 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2">
          <span class="icon-[lucide--coins] size-4"></span>
          Token Usage
        </h4>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div class="text-center">
            <div class="text-lg font-mono">${this.formatNumber(data.usage.prompt_tokens)}</div>
            <div class="text-xs text-base-content/60">Prompt</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-mono">${this.formatNumber(data.usage.completion_tokens)}</div>
            <div class="text-xs text-base-content/60">Completion</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-mono">${this.formatNumber(data.usage.total_tokens)}</div>
            <div class="text-xs text-base-content/60">Total</div>
          </div>
        </div>
      </div>
      ` : ''}

      <!-- World Info Budget Alert -->
      ${data.lore_budget_exceeded ? `
      <div class="bg-warning/10 border border-warning/20 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2 text-warning">
          <span class="icon-[lucide--alert-triangle] size-4"></span>
          World Info Budget Exceeded
        </h4>
        <div class="space-y-1 text-sm">
          <p class="text-warning/80">
            ${data.lore_budget_dropped_count} World Info ${data.lore_budget_dropped_count === 1 ? 'entry was' : 'entries were'} dropped due to token budget constraints.
          </p>
          <div class="flex justify-between text-base-content/70">
            <span>Entries Selected</span>
            <span>${data.lore_selected_count || 0}</span>
          </div>
          <div class="flex justify-between text-base-content/70">
            <span>Tokens Used</span>
            <span>${this.formatNumber(data.lore_used_tokens)}</span>
          </div>
          <div class="flex justify-between text-base-content/70">
            <span>Budget</span>
            <span>${data.lore_budget === 'unlimited' ? 'Unlimited' : this.formatNumber(data.lore_budget)}</span>
          </div>
        </div>
      </div>
      ` : data.lore_selected_count !== undefined ? `
      <div class="bg-base-200 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2">
          <span class="icon-[lucide--book-open] size-4"></span>
          World Info
        </h4>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div class="text-center">
            <div class="text-lg font-mono">${data.lore_selected_count || 0}</div>
            <div class="text-xs text-base-content/60">Entries</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-mono">${this.formatNumber(data.lore_used_tokens)}</div>
            <div class="text-xs text-base-content/60">Tokens</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-mono">${data.lore_budget === 'unlimited' ? '∞' : this.formatNumber(data.lore_budget)}</div>
            <div class="text-xs text-base-content/60">Budget</div>
          </div>
        </div>
      </div>
      ` : ''}

      <!-- Error Details -->
      ${data.error ? `
      <div class="bg-error/10 border border-error/20 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2 text-error">
          <span class="icon-[lucide--alert-circle] size-4"></span>
          Error
        </h4>
        <div class="space-y-1 text-sm">
          <div class="flex justify-between">
            <span class="text-error/70">Code</span>
            <span class="font-mono">${data.error.code || '-'}</span>
          </div>
          ${data.error.message ? `
          <div>
            <span class="text-error/70 block mb-1">Message</span>
            <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${this.escapeHtml(data.error.message)}</code>
          </div>
          ` : ''}
          ${data.error.user_message && data.error.user_message !== data.error.message ? `
          <div>
            <span class="text-error/70 block mb-1">User Message</span>
            <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${this.escapeHtml(data.error.user_message)}</code>
          </div>
          ` : ''}
        </div>
      </div>
      ` : ''}

      <!-- Token Inspector -->
      ${data.tokenized_prompt ? `
      <div class="bg-base-200 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2">
          <span class="icon-[lucide--hash] size-4"></span>
          Token Inspector
          <span class="badge badge-xs badge-ghost">${data.tokenized_prompt.length} messages</span>
        </h4>
        <div class="max-h-80 overflow-y-auto space-y-3">
          ${data.tokenized_prompt.map((msg, idx) => `
            <div class="border rounded-lg ${this.roleClass(msg.role)} overflow-hidden">
              <div class="px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm ${this.roleBadgeClass(msg.role)}">${this.capitalizeFirst(msg.role)}</span>
                  ${msg.name ? `<span class="text-xs text-base-content/50">${this.escapeHtml(msg.name)}</span>` : ''}
                </div>
                <span class="text-xs text-base-content/40">${msg.token_count || msg.tokens?.length || 0} tokens</span>
              </div>
              <div class="p-3 font-mono text-sm leading-relaxed">
                ${msg.tokens?.map((token, tokenIdx) => `<span class="token-chunk tooltip cursor-help" data-tip="ID: ${token.id}">${this.escapeHtml(token.text).replace(/\n/g, '↵\n')}</span>`).join('') || '<span class="text-base-content/40 italic">No tokens</span>'}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
      ` : ''}

      <!-- Logprobs (Token Probabilities) -->
      ${data.logprobs ? `
      <div class="bg-base-200 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2">
          <span class="icon-[lucide--bar-chart-3] size-4"></span>
          Token Probabilities
          <span class="badge badge-xs badge-ghost">${data.logprobs.length} tokens</span>
        </h4>
        <div class="max-h-60 overflow-y-auto">
          <div class="font-mono text-sm leading-relaxed">
            ${data.logprobs.map(token => `<span class="logprob-token ${this.logprobClass(token.logprob)} tooltip cursor-help" data-tip="${this.formatLogprobTooltip(token)}">${this.escapeHtml(token.token || '')}</span>`).join('')}
          </div>
        </div>
      </div>
      ` : ''}

      <!-- Prompt Snapshot (JSON) -->
      ${data.prompt_snapshot ? `
      <div class="bg-base-200 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2">
          <span class="icon-[lucide--message-square] size-4"></span>
          Prompt Snapshot (JSON)
          <span class="badge badge-xs badge-ghost">${data.prompt_snapshot.length} messages</span>
        </h4>
        <div class="max-h-60 overflow-y-auto">
          <pre class="text-xs bg-base-300 rounded p-2 overflow-x-auto whitespace-pre-wrap">${this.escapeHtml(JSON.stringify(data.prompt_snapshot, null, 2))}</pre>
        </div>
      </div>
      ` : `
      <div class="bg-base-200 rounded-lg p-3 text-sm text-base-content/50">
        <span class="icon-[lucide--info] size-4 inline"></span>
        Prompt snapshot not available. Enable <code>conversation.snapshot_prompt</code> setting to capture prompts.
      </div>
      `}

      <!-- Queue Info (for queued runs) -->
      ${data.status === 'queued' ? `
      <div class="bg-info/10 border border-info/20 rounded-lg p-3 space-y-2">
        <h4 class="font-semibold text-sm flex items-center gap-2 text-info">
          <span class="icon-[lucide--clock] size-4"></span>
          Queue Info
        </h4>
        <div class="space-y-1 text-sm">
          ${data.run_after ? `
          <div class="flex justify-between">
            <span class="text-info/70">Run After</span>
            <span>${this.formatTime(data.run_after)}</span>
          </div>
          ` : ''}
          ${data.expected_last_message_id ? `
          <div class="flex justify-between">
            <span class="text-info/70">Expected Last Message ID</span>
            <span class="font-mono">${data.expected_last_message_id}</span>
          </div>
          ` : ''}
        </div>
      </div>
      ` : ''}
    `

    this.contentTarget.innerHTML = html
  }

  /**
   * Copy the prompt snapshot JSON to clipboard.
   */
  async copyPromptJson() {
    if (!this.currentRunData?.prompt_snapshot) {
      this.showToast("No prompt snapshot available", "warning")
      return
    }

    try {
      const json = JSON.stringify(this.currentRunData.prompt_snapshot, null, 2)
      await navigator.clipboard.writeText(json)
      this.showToast("Prompt JSON copied to clipboard", "success")
    } catch (err) {
      console.error("Failed to copy:", err)
      this.showToast("Failed to copy to clipboard", "error")
    }
  }

  /**
   * Show a toast notification using the global toast:show event.
   */
  showToast(message, type = "info") {
    window.dispatchEvent(new CustomEvent("toast:show", {
      detail: { message, type, duration: 3000 },
      bubbles: true,
      cancelable: true
    }))
  }

  // Helper methods

  statusBadgeClass(status) {
    const classes = {
      succeeded: "badge-success",
      failed: "badge-error",
      canceled: "badge-warning",
      running: "badge-info",
      queued: "badge-ghost"
    }
    return classes[status] || "badge-ghost"
  }

  formatTime(timestamp) {
    if (!timestamp) return "-"
    const date = new Date(timestamp)
    return date.toLocaleString()
  }

  calculateDuration(start, end) {
    if (!start || !end) return "-"
    const ms = new Date(end) - new Date(start)
    if (ms < 1000) return `${ms}ms`
    return `${(ms / 1000).toFixed(2)}s`
  }

  formatNumber(num) {
    if (num === undefined || num === null) return "-"
    return num.toLocaleString()
  }

  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  capitalizeFirst(str) {
    if (!str) return ""
    return str.charAt(0).toUpperCase() + str.slice(1)
  }

  roleClass(role) {
    const classes = {
      system: "bg-warning/10 border-warning/30",
      assistant: "bg-secondary/10 border-secondary/30",
      user: "bg-primary/10 border-primary/30"
    }
    return classes[role] || "bg-base-200 border-base-300"
  }

  roleBadgeClass(role) {
    const classes = {
      system: "badge-warning",
      assistant: "badge-secondary",
      user: "badge-primary"
    }
    return classes[role] || "badge-ghost"
  }

  /**
   * Get CSS class for logprob token based on probability.
   * Higher probability (closer to 0) = greener color.
   * Lower probability (more negative) = redder color.
   *
   * @param {number} logprob - The log probability value
   * @returns {string} CSS class name
   */
  logprobClass(logprob) {
    if (logprob === undefined || logprob === null) return ""
    // logprob is typically negative (log of probability)
    // -0.1 to 0 = very high prob (>90%)
    // -0.5 to -0.1 = high prob (60-90%)
    // -1.0 to -0.5 = medium prob (37-60%)
    // -2.0 to -1.0 = low prob (14-37%)
    // < -2.0 = very low prob (<14%)
    if (logprob > -0.1) return "prob-very-high"
    if (logprob > -0.5) return "prob-high"
    if (logprob > -1.0) return "prob-medium"
    if (logprob > -2.0) return "prob-low"
    return "prob-very-low"
  }

  /**
   * Format logprob tooltip with probability percentage and alternatives.
   *
   * @param {Object} tokenData - Token data with logprob and top_logprobs
   * @returns {string} Formatted tooltip text
   */
  formatLogprobTooltip(tokenData) {
    if (!tokenData) return ""
    const prob = tokenData.logprob !== undefined
      ? `${(Math.exp(tokenData.logprob) * 100).toFixed(1)}%`
      : "N/A"

    let tooltip = `Prob: ${prob}`

    // Add top alternatives if available
    if (tokenData.top_logprobs && Array.isArray(tokenData.top_logprobs)) {
      const alts = tokenData.top_logprobs
        .slice(0, 3)
        .map(alt => `${this.escapeHtml(alt.token)}: ${(Math.exp(alt.logprob) * 100).toFixed(1)}%`)
        .join(', ')
      if (alts) {
        tooltip += ` | Alts: ${alts}`
      }
    }

    return tooltip
  }
}
