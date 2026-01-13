import { escapeHtml } from "../../dom_helpers"
import {
  calculateDuration,
  formatLogprobTooltip,
  formatNumber,
  formatTime,
  logprobClass,
  statusBadgeClass
} from "./formatters"

export function renderOverviewTab(data) {
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
                <span class="badge badge-sm ${statusBadgeClass(data.status)}">${data.status}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Type</span>
                <span>${data.type_label || "-"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Trigger</span>
                <span>${data.trigger || "-"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Created</span>
                <span>${formatTime(data.created_at)}</span>
              </div>
              ${data.started_at ? `
              <div class="flex justify-between">
                <span class="text-base-content/60">Started</span>
                <span>${formatTime(data.started_at)}</span>
              </div>
              ` : ""}
              ${data.finished_at ? `
              <div class="flex justify-between">
                <span class="text-base-content/60">Finished</span>
                <span>${formatTime(data.finished_at)}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Duration</span>
                <span>${calculateDuration(data.started_at, data.finished_at)}</span>
              </div>
              ` : ""}
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
                <span>${data.speaker_name || data.speaker_membership_id || "-"}</span>
              </div>
              ${data.generation_params ? `
              <div class="flex justify-between">
                <span class="text-base-content/60">Provider</span>
                <span>${data.generation_params.provider_name || "-"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Model</span>
                <span class="font-mono text-xs">${data.generation_params.model || "-"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Max Tokens</span>
                <span>${data.generation_params.max_response_tokens || "-"}</span>
              </div>
              ${data.generation_params.temperature !== undefined ? `
              <div class="flex justify-between">
                <span class="text-base-content/60">Temperature</span>
                <span>${data.generation_params.temperature}</span>
              </div>
              ` : ""}
              ` : ""}
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
              <div class="text-lg font-mono">${formatNumber(data.usage.prompt_tokens)}</div>
              <div class="text-xs text-base-content/60">Prompt</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-mono">${formatNumber(data.usage.completion_tokens)}</div>
              <div class="text-xs text-base-content/60">Completion</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-mono">${formatNumber(data.usage.total_tokens)}</div>
              <div class="text-xs text-base-content/60">Total</div>
            </div>
          </div>
        </div>
        ` : ""}

        <!-- World Info Budget Alert -->
        ${data.lore_budget_exceeded ? `
        <div class="bg-warning/10 border border-warning/20 rounded-lg p-3 space-y-2">
          <h4 class="font-semibold text-sm flex items-center gap-2 text-warning">
            <span class="icon-[lucide--alert-triangle] size-4"></span>
            World Info Budget Exceeded
          </h4>
          <div class="space-y-1 text-sm">
            <p class="text-warning/80">
              ${data.lore_budget_dropped_count} World Info ${data.lore_budget_dropped_count === 1 ? "entry was" : "entries were"} dropped due to token budget constraints.
            </p>
            <div class="flex justify-between text-base-content/70">
              <span>Entries Selected</span>
              <span>${data.lore_selected_count || 0}</span>
            </div>
            <div class="flex justify-between text-base-content/70">
              <span>Tokens Used</span>
              <span>${formatNumber(data.lore_used_tokens)}</span>
            </div>
            <div class="flex justify-between text-base-content/70">
              <span>Budget</span>
              <span>${data.lore_budget === "unlimited" ? "Unlimited" : formatNumber(data.lore_budget)}</span>
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
              <div class="text-lg font-mono">${formatNumber(data.lore_used_tokens)}</div>
              <div class="text-xs text-base-content/60">Tokens</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-mono">${data.lore_budget === "unlimited" ? "∞" : formatNumber(data.lore_budget)}</div>
              <div class="text-xs text-base-content/60">Budget</div>
            </div>
          </div>
        </div>
        ` : ""}

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
              <span class="font-mono">${data.error.code || "-"}</span>
            </div>
            ${data.error.message ? `
            <div>
              <span class="text-error/70 block mb-1">Message</span>
              <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${escapeHtml(data.error.message)}</code>
            </div>
            ` : ""}
            ${data.error.user_message && data.error.user_message !== data.error.message ? `
            <div>
              <span class="text-error/70 block mb-1">User Message</span>
              <code class="block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap">${escapeHtml(data.error.user_message)}</code>
            </div>
            ` : ""}
          </div>
        </div>
        ` : ""}

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
              ${data.logprobs.map(token => `<span class="logprob-token ${logprobClass(token.logprob)} tooltip cursor-help" data-tip="${formatLogprobTooltip(token)}">${escapeHtml(token.token || "")}</span>`).join("")}
            </div>
          </div>
        </div>
        ` : ""}

        <!-- Queue Info (for queued runs) -->
        ${data.status === "queued" ? `
        <div class="bg-info/10 border border-info/20 rounded-lg p-3 space-y-2">
          <h4 class="font-semibold text-sm flex items-center gap-2 text-info">
            <span class="icon-[lucide--clock] size-4"></span>
            Queue Info
          </h4>
          <div class="space-y-1 text-sm">
            ${data.run_after ? `
            <div class="flex justify-between">
              <span class="text-info/70">Run After</span>
              <span>${formatTime(data.run_after)}</span>
            </div>
            ` : ""}
            ${data.expected_last_message_id ? `
            <div class="flex justify-between">
              <span class="text-info/70">Expected Last Message ID</span>
              <span class="font-mono">${data.expected_last_message_id}</span>
            </div>
            ` : ""}
          </div>
        </div>
        ` : ""}
      </div>
    `
}
