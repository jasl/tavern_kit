import { renderOverviewTab } from "./overview_tab"
import { renderPromptSnapshotTab } from "./prompt_snapshot_tab"
import { renderTokenInspectorTab } from "./token_inspector_tab"

export function renderRunDetailModalContent(data) {
  const tabId = `run_detail_tabs_${Date.now()}`

  return `
      <div role="tablist" class="tabs tabs-box">
        <!-- Overview Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Overview" checked="checked" />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${renderOverviewTab(data)}
        </div>

        <!-- Prompt Snapshot Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Prompt JSON" ${!data.prompt_snapshot ? "disabled" : ""} />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${renderPromptSnapshotTab(data)}
        </div>

        <!-- Token Inspector Tab -->
        <input type="radio" name="${tabId}" role="tab" class="tab" aria-label="Token Inspector" ${!data.tokenized_prompt ? "disabled" : ""} />
        <div role="tabpanel" class="tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto" style="max-height: calc(70vh - 120px);">
          ${renderTokenInspectorTab(data)}
        </div>
      </div>
    `
}
