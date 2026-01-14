import { renderOverviewTab } from "./overview_tab"
import { renderPromptSnapshotTab } from "./prompt_snapshot_tab"
import { renderTokenInspectorTab } from "./token_inspector_tab"
import { el } from "./dom"

export function renderRunDetailModalContent(data) {
  const tabId = `run_detail_tabs_${Date.now()}`

  const container = el("div", {
    className: "tabs tabs-box",
    attrs: { role: "tablist" }
  })

  function appendTab({ label, checked, disabled, content }) {
    const input = el("input", {
      className: "tab",
      attrs: {
        type: "radio",
        name: tabId,
        role: "tab",
        "aria-label": label
      }
    })
    if (checked) input.checked = true
    if (disabled) input.disabled = true

    const panel = el("div", {
      className: "tab-content p-4 bg-base-100 border-base-300 rounded-box overflow-y-auto",
      attrs: { role: "tabpanel" }
    })
    panel.style.maxHeight = "calc(70vh - 120px)"
    panel.append(content)

    container.append(input, panel)
  }

  appendTab({
    label: "Overview",
    checked: true,
    disabled: false,
    content: renderOverviewTab(data)
  })

  appendTab({
    label: "Prompt JSON",
    checked: false,
    disabled: !data.prompt_snapshot,
    content: renderPromptSnapshotTab(data)
  })

  appendTab({
    label: "Token Inspector",
    checked: false,
    disabled: !data.tokenized_prompt,
    content: renderTokenInspectorTab(data)
  })

  return container
}
