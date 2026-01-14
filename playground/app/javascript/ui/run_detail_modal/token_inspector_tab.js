import { capitalizeFirst, roleBadgeClass, roleClass } from "./formatters"
import { el, lucide } from "./dom"

export function renderTokenInspectorTab(data) {
  if (!data.tokenized_prompt) {
    return el("div", { className: "flex flex-col items-center justify-center py-12 text-base-content/50" }, [
      lucide("hash", "size-12 mb-4"),
      el("p", { className: "text-sm", text: "Token data not available." }),
      el("p", { className: "text-xs mt-1", text: "Tokenization is performed when prompt snapshot is enabled." })
    ])
  }

  const root = el("div", { className: "space-y-4" })

  const totalTokens = data.tokenized_prompt.reduce((sum, msg) => sum + (msg.token_count || msg.tokens?.length || 0), 0)

  const headerRow = el("div", { className: "flex items-center justify-between text-sm" })
  headerRow.append(
    el("span", { className: "text-base-content/60" }, [
      lucide("hash", "size-4 mr-1"),
      `${data.tokenized_prompt.length} messages`
    ]),
    el("span", { className: "badge badge-info badge-outline badge-sm gap-1" }, [
      lucide("hash", "size-3"),
      `${totalTokens} total tokens`
    ])
  )

  root.append(headerRow)

  const list = el("div", { className: "space-y-3" })
  for (const msg of data.tokenized_prompt) {
    const role = msg.role || "unknown"
    const tokensCount = msg.token_count || msg.tokens?.length || 0

    const card = el("div", { className: `border rounded-lg ${roleClass(role)} overflow-hidden` })
    const cardHeader = el("div", { className: "px-3 py-2 bg-base-100/50 border-b border-inherit flex items-center justify-between" })

    const left = el("div", { className: "flex items-center gap-2" }, [
      el("span", { className: `badge badge-sm ${roleBadgeClass(role)}`, text: capitalizeFirst(role) })
    ])
    if (msg.name) left.append(el("span", { className: "text-xs text-base-content/50", text: msg.name }))

    cardHeader.append(
      left,
      el("span", { className: "text-xs text-base-content/40", text: `${tokensCount} tokens` })
    )

    const body = el("div", { className: "p-3 font-mono text-sm leading-relaxed" })
    if (msg.tokens?.length) {
      for (const token of msg.tokens) {
        body.append(
          el("span", {
            className: "token-chunk tooltip cursor-help",
            dataset: { tip: `ID: ${token.id}` },
            text: (token.text || "").replace(/\n/g, "↵\n")
          })
        )
      }
    } else {
      body.append(el("span", { className: "text-base-content/40 italic", text: "No tokens" }))
    }

    card.append(cardHeader, body)
    list.append(card)
  }

  root.append(list)
  return root
}
