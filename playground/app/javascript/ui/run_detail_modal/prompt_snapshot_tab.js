import { escapeHtml } from "../../dom_helpers"
import { capitalizeFirst, roleBadgeClass, roleClass } from "./formatters"

export function renderPromptSnapshotTab(data) {
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
            const role = message.role || "unknown"
            const roleClassName = roleClass(role)
            const roleBadgeClassName = roleBadgeClass(role)
            return `
              <div class="border rounded-lg ${roleClassName} overflow-hidden">
                <div class="px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between">
                  <span class="badge badge-sm ${roleBadgeClassName}">${capitalizeFirst(role)}</span>
                  ${message.name ? `<span class="text-xs text-base-content/50">${escapeHtml(message.name)}</span>` : ""}
                </div>
                <div class="p-3">
                  <pre class="text-sm whitespace-pre-wrap break-words font-mono text-base-content/80">${escapeHtml(message.content || "")}</pre>
                </div>
              </div>
            `
          }).join("")}
        </div>
      </div>
    `
}
