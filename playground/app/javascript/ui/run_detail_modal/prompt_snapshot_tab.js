import { capitalizeFirst, roleBadgeClass, roleClass } from "./formatters"
import { el, lucide } from "./dom"

export function renderPromptSnapshotTab(data) {
  if (!data.prompt_snapshot) {
    return el("div", { className: "flex flex-col items-center justify-center py-12 text-base-content/50" }, [
      lucide("message-square-off", "size-12 mb-4"),
      el("p", { className: "text-sm", text: "Prompt snapshot not available." }),
      el("p", { className: "text-xs mt-1" }, [
        "Enable ",
        el("code", { className: "bg-base-200 px-1 rounded", text: "conversation.snapshot_prompt" }),
        " setting to capture prompts."
      ])
    ])
  }

  const root = el("div", { className: "space-y-4" })

  const headerRow = el("div", { className: "flex items-center justify-between text-sm" })
  const messageCount = el("span", { className: "text-base-content/60" }, [
    lucide("message-square", "size-4 mr-1"),
    `${data.prompt_snapshot.length} messages`
  ])

  const copyButton = el("button", {
    className: "btn btn-xs btn-ghost gap-1",
    attrs: { type: "button", "data-action": "run-detail-modal#copyPromptJson" }
  }, [
    lucide("clipboard-copy", "size-3"),
    "Copy JSON"
  ])

  headerRow.append(messageCount, copyButton)
  root.append(headerRow)

  const list = el("div", { className: "space-y-3" })
  for (const message of data.prompt_snapshot) {
    const role = message.role || "unknown"
    const card = el("div", { className: `border rounded-lg ${roleClass(role)} overflow-hidden` })
    const cardHeader = el("div", { className: "px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between" })
    cardHeader.append(
      el("span", { className: `badge badge-sm ${roleBadgeClass(role)}`, text: capitalizeFirst(role) })
    )
    if (message.name) {
      cardHeader.append(el("span", { className: "text-xs text-base-content/50", text: message.name }))
    }

    const cardBody = el("div", { className: "p-3" }, [
      el("pre", {
        className: "text-sm whitespace-pre-wrap break-words font-mono text-base-content/80",
        text: message.content || ""
      })
    ])

    card.append(cardHeader, cardBody)
    list.append(card)
  }

  root.append(list)
  return root
}
