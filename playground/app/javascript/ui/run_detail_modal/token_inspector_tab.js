import { escapeHtml } from "../../dom_helpers"
import { capitalizeFirst, roleBadgeClass, roleClass } from "./formatters"

export function renderTokenInspectorTab(data) {
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
            <div class="border rounded-lg ${roleClass(msg.role)} overflow-hidden">
              <div class="px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm ${roleBadgeClass(msg.role)}">${capitalizeFirst(msg.role)}</span>
                  ${msg.name ? `<span class="text-xs text-base-content/50">${escapeHtml(msg.name)}</span>` : ""}
                </div>
                <span class="text-xs text-base-content/40">${msg.token_count || msg.tokens?.length || 0} tokens</span>
              </div>
              <div class="p-3 font-mono text-sm leading-relaxed">
                ${msg.tokens?.map((token, _tokenIdx) => `<span class="token-chunk tooltip cursor-help" data-tip="ID: ${token.id}">${escapeHtml(token.text).replace(/\\n/g, "↵\\n")}</span>`).join("") || '<span class="text-base-content/40 italic">No tokens</span>'}
              </div>
            </div>
          `).join("")}
        </div>
      </div>
    `
}
