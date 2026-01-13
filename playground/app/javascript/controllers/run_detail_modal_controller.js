import { Controller } from "@hotwired/stimulus"
import { showToast } from "../request_helpers"
import { copyTextToClipboard, escapeHtml } from "../dom_helpers"

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
  static targets = ["content"]

  // Store current run data for copy functionality
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
  }

  /**
   * Copy prompt snapshot JSON to clipboard.
   * Called by the Copy JSON button in the Prompt JSON tab.
   */
  async copyPromptJson() {
    if (!this.currentRunData?.prompt_snapshot) {
      showToast("No prompt snapshot available", "warning")
      return
    }

    const json = JSON.stringify(this.currentRunData.prompt_snapshot, null, 2)
    const ok = await copyTextToClipboard(json)
    showToast(ok ? "Copied to clipboard" : "Failed to copy", ok ? "success" : "error")
  }

  /**
   * Render the run details content with tabs.
   *
   * @param {Object} data - The run data
   */
  renderContent(data) {
    if (!this.hasContentTarget) return

    // Generate unique ID for this modal's tabs to avoid conflicts
    const tabId = `run_detail_tabs_${Date.now()}`

    const html = `
      <div role="tablist" class="tabs tabs-box">
        <!-- Overview Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Overview" checked="checked" />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${this.renderOverviewTab(data)}
        </div>

        <!-- Prompt Snapshot Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Prompt JSON" ${!data.prompt_snapshot ? 'disabled' : ''} />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${this.renderPromptSnapshotTab(data)}
        </div>

        <!-- Token Inspector Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Token Inspector" ${!data.tokenized_prompt ? 'disabled' : ''} />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${this.renderTokenInspectorTab(data)}
        </div>
      </div>
    `

    this.contentTarget.innerHTML = html
  }

  /**
   * Render the Overview tab content.
   */
  renderOverviewTab(data) {
    return `
      <div class="space-y-4">
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
                <span class="text-base-content/60">Type</span>
                <span>${data.type_label || '-'}</span>
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
              <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${escapeHtml(data.error.message)}</code>
            </div>
            ` : ''}
            ${data.error.user_message && data.error.user_message !== data.error.message ? `
            <div>
              <span class="text-error/70 block mb-1">User Message</span>
              <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${escapeHtml(data.error.user_message)}</code>
            </div>
            ` : ''}
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
              ${data.logprobs.map(token => `<span class="logprob-token ${this.logprobClass(token.logprob)} tooltip cursor-help" data-tip="${this.formatLogprobTooltip(token)}">${escapeHtml(token.token || '')}</span>`).join('')}
            </div>
          </div>
        </div>
        ` : ''}

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
      </div>
    `
  }

  /**
   * Render the Prompt Snapshot tab content.
   */
  renderPromptSnapshotTab(data) {
    if (!data.prompt_snapshot) {
      return `
        <div class="flex flex-col items-center justify-center py-12 text-base-content/50">
          <span class="icon-[lucide--message-square-off] size-12 mb-4"></span>
          <p class="text-sm">Prompt snapshot not available.</p>
          <p class="text-xs mt-1">Enable <code class="bg-base-200 px-1 rounded">conversation.snapshot_prompt</code> setting to capture prompts.</p>
        </div>
      `
    }

    return `
      <div class="space-y-4">
        <div class="flex items-center justify-between text-sm">
          <span class="text-base-content/60">
            <span class="icon-[lucide--message-square] size-4 mr-1"></span>
            ${data.prompt_snapshot.length} messages
          </span>
          <button type="button"
                  class="btn btn-xs btn-ghost gap-1"
                  data-action="run-detail-modal#copyPromptJson">
            <span class="icon-[lucide--clipboard-copy] size-3"></span>
            Copy JSON
          </button>
        </div>

        <!-- Messages list similar to Preview modal -->
        <div class="space-y-3">
          ${data.prompt_snapshot.map((message, _index) => {
            const role = message.role || 'unknown'
            const roleClass = this.roleClass(role)
            const roleBadgeClass = this.roleBadgeClass(role)
            return `
              <div class="border rounded-lg ${roleClass} overflow-hidden">
                <div class="px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between">
                  <span class="badge badge-sm ${roleBadgeClass}">${this.capitalizeFirst(role)}</span>
                  ${message.name ? `<span class="text-xs text-base-content/50">${escapeHtml(message.name)}</span>` : ''}
                </div>
                <div class="p-3">
                  <pre class="text-sm whitespace-pre-wrap break-words font-mono text-base-content/80">${escapeHtml(message.content || '')}</pre>
                </div>
              </div>
            `
          }).join('')}
        </div>
      </div>
    `
  }

  /**
   * Render the Token Inspector tab content.
   */
  renderTokenInspectorTab(data) {
    if (!data.tokenized_prompt) {
      return `
        <div class="flex flex-col items-center justify-center py-12 text-base-content/50">
          <span class="icon-[lucide--hash] size-12 mb-4"></span>
          <p class="text-sm">Token data not available.</p>
          <p class="text-xs mt-1">Tokenization is performed when prompt snapshot is enabled.</p>
        </div>
      `
    }

    return `
      <div class="space-y-4">
        <div class="flex items-center justify-between text-sm">
          <span class="text-base-content/60">
            <span class="icon-[lucide--hash] size-4 mr-1"></span>
            ${data.tokenized_prompt.length} messages
          </span>
          <span class="badge badge-info badge-outline badge-sm gap-1">
            <span class="icon-[lucide--hash] size-3"></span>
            ${data.tokenized_prompt.reduce((sum, msg) => sum + (msg.token_count || msg.tokens?.length || 0), 0)} total tokens
          </span>
        </div>

        <div class="space-y-3">
          ${data.tokenized_prompt.map((msg, _idx) => `
            <div class="border rounded-lg ${this.roleClass(msg.role)} overflow-hidden">
              <div class="px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm ${this.roleBadgeClass(msg.role)}">${this.capitalizeFirst(msg.role)}</span>
                  ${msg.name ? `<span class="text-xs text-base-content/50">${escapeHtml(msg.name)}</span>` : ''}
                </div>
                <span class="text-xs text-base-content/40">${msg.token_count || msg.tokens?.length || 0} tokens</span>
              </div>
              <div class="p-3 font-mono text-sm leading-relaxed">
                ${msg.tokens?.map((token, _tokenIdx) => `<span class="token-chunk tooltip cursor-help" data-tip="ID: ${token.id}">${escapeHtml(token.text).replace(/\n/g, '↵\n')}</span>`).join('') || '<span class="text-base-content/40 italic">No tokens</span>'}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `
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
        .map(alt => `${escapeHtml(alt.token)}: ${(Math.exp(alt.logprob) * 100).toFixed(1)}%`)
        .join(', ')
      if (alts) {
        tooltip += ` | Alts: ${alts}`
      }
    }

    return tooltip
  }
}
