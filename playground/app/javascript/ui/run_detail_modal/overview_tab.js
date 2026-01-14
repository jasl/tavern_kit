import {
  calculateDuration,
  formatLogprobTooltip,
  formatNumber,
  formatTime,
  logprobClass,
  statusBadgeClass
} from "./formatters"
import { el, lucide } from "./dom"

export function renderOverviewTab(data) {
  const root = el("div", { className: "space-y-4" })

  function kvRow(label, value, { labelClassName = "text-base-content/60", valueClassName = null } = {}) {
    const valueNode = value instanceof Node ? value : el("span", { text: value })
    if (valueClassName) valueNode.classList.add(...valueClassName.split(" "))

    return el("div", { className: "flex justify-between" }, [
      el("span", { className: labelClassName, text: label }),
      valueNode
    ])
  }

  function sectionHeader(iconName, title, { className = "font-semibold text-sm flex items-center gap-2", colorClass = null } = {}) {
    const header = el("h4", { className })
    if (colorClass) header.classList.add(...colorClass.split(" "))
    header.append(lucide(iconName, "size-4"), title)
    return header
  }

  function baseCard(title, iconName) {
    return el("div", { className: "bg-base-200 rounded-lg p-3 space-y-2" }, [
      sectionHeader(iconName, title)
    ])
  }

  const topGrid = el("div", { className: "grid grid-cols-2 gap-4" })

  // Status & Timing
  const statusCard = baseCard("Status", "info")
  const statusBody = el("div", { className: "space-y-1 text-sm" })
  statusBody.append(
    kvRow("Status", el("span", { className: `badge badge-sm ${statusBadgeClass(data.status)}`, text: data.status || "-" })),
    kvRow("Type", data.type_label || "-"),
    kvRow("Trigger", data.trigger || "-"),
    kvRow("Created", formatTime(data.created_at))
  )
  if (data.started_at) statusBody.append(kvRow("Started", formatTime(data.started_at)))
  if (data.finished_at) {
    statusBody.append(
      kvRow("Finished", formatTime(data.finished_at)),
      kvRow("Duration", calculateDuration(data.started_at, data.finished_at))
    )
  }
  statusCard.append(statusBody)

  // Speaker & Generation
  const generationCard = baseCard("Generation", "user")
  const generationBody = el("div", { className: "space-y-1 text-sm" })
  generationBody.append(
    kvRow("Speaker", data.speaker_name || data.speaker_membership_id || "-")
  )

  if (data.generation_params) {
    generationBody.append(
      kvRow("Provider", data.generation_params.provider_name || "-"),
      kvRow("Model", el("span", { className: "font-mono text-xs", text: data.generation_params.model || "-" })),
      kvRow("Max Tokens", data.generation_params.max_response_tokens || "-")
    )

    if (data.generation_params.temperature !== undefined) {
      generationBody.append(kvRow("Temperature", data.generation_params.temperature))
    }
  }
  generationCard.append(generationBody)

  topGrid.append(statusCard, generationCard)
  root.append(topGrid)

  // Token Usage
  if (data.usage) {
    const tokenSection = el("div", { className: "bg-base-200 rounded-lg p-3 space-y-2" }, [
      sectionHeader("coins", "Token Usage")
    ])

    const tokenGrid = el("div", { className: "grid grid-cols-3 gap-4 text-sm" })
    function tokenCell(value, label) {
      return el("div", { className: "text-center" }, [
        el("div", { className: "text-lg font-mono", text: formatNumber(value) }),
        el("div", { className: "text-xs text-base-content/60", text: label })
      ])
    }

    tokenGrid.append(
      tokenCell(data.usage.prompt_tokens, "Prompt"),
      tokenCell(data.usage.completion_tokens, "Completion"),
      tokenCell(data.usage.total_tokens, "Total")
    )

    tokenSection.append(tokenGrid)
    root.append(tokenSection)
  }

  // World Info Budget / Summary
  if (data.lore_budget_exceeded) {
    const droppedCount = data.lore_budget_dropped_count || 0
    const infoText = `${droppedCount} World Info ${droppedCount === 1 ? "entry was" : "entries were"} dropped due to token budget constraints.`

    const wiSection = el("div", { className: "bg-warning/10 border border-warning/20 rounded-lg p-3 space-y-2" }, [
      sectionHeader("alert-triangle", "World Info Budget Exceeded", { colorClass: "text-warning" })
    ])

    const body = el("div", { className: "space-y-1 text-sm" }, [
      el("p", { className: "text-warning/80", text: infoText }),
      el("div", { className: "flex justify-between text-base-content/70" }, [
        el("span", { text: "Entries Selected" }),
        el("span", { text: data.lore_selected_count || 0 })
      ]),
      el("div", { className: "flex justify-between text-base-content/70" }, [
        el("span", { text: "Tokens Used" }),
        el("span", { text: formatNumber(data.lore_used_tokens) })
      ]),
      el("div", { className: "flex justify-between text-base-content/70" }, [
        el("span", { text: "Budget" }),
        el("span", { text: data.lore_budget === "unlimited" ? "Unlimited" : formatNumber(data.lore_budget) })
      ])
    ])

    wiSection.append(body)
    root.append(wiSection)
  } else if (data.lore_selected_count !== undefined) {
    const wiSection = el("div", { className: "bg-base-200 rounded-lg p-3 space-y-2" }, [
      sectionHeader("book-open", "World Info")
    ])

    const grid = el("div", { className: "grid grid-cols-3 gap-4 text-sm" })
    function wiCell(value, label) {
      return el("div", { className: "text-center" }, [
        el("div", { className: "text-lg font-mono", text: value }),
        el("div", { className: "text-xs text-base-content/60", text: label })
      ])
    }

    grid.append(
      wiCell(data.lore_selected_count || 0, "Entries"),
      wiCell(formatNumber(data.lore_used_tokens), "Tokens"),
      wiCell(data.lore_budget === "unlimited" ? "∞" : formatNumber(data.lore_budget), "Budget")
    )

    wiSection.append(grid)
    root.append(wiSection)
  }

  // Error Details
  if (data.error) {
    const errorSection = el("div", { className: "bg-error/10 border border-error/20 rounded-lg p-3 space-y-2" }, [
      sectionHeader("alert-circle", "Error", { colorClass: "text-error" })
    ])

    const body = el("div", { className: "space-y-1 text-sm" })
    body.append(
      kvRow("Code", el("span", { className: "font-mono", text: data.error.code || "-" }), { labelClassName: "text-error/70" })
    )

    if (data.error.message) {
      body.append(
        el("div", {}, [
          el("span", { className: "text-error/70 block mb-1", text: "Message" }),
          el("code", { className: "block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap", text: data.error.message })
        ])
      )
    }

    if (data.error.user_message && data.error.user_message !== data.error.message) {
      body.append(
        el("div", {}, [
          el("span", { className: "text-error/70 block mb-1", text: "User Message" }),
          el("code", { className: "block bg-base-300 rounded p-2 text-xs whitespace-pre-wrap", text: data.error.user_message })
        ])
      )
    }

    errorSection.append(body)
    root.append(errorSection)
  }

  // Logprobs (Token Probabilities)
  if (data.logprobs) {
    const section = el("div", { className: "bg-base-200 rounded-lg p-3 space-y-2" })
    const header = sectionHeader("bar-chart-3", "Token Probabilities")
    header.append(el("span", { className: "badge badge-xs badge-ghost", text: `${data.logprobs.length} tokens` }))
    section.append(header)

    const scroll = el("div", { className: "max-h-60 overflow-y-auto" })
    const tokensEl = el("div", { className: "font-mono text-sm leading-relaxed" })

    for (const token of data.logprobs) {
      tokensEl.append(
        el("span", {
          className: `logprob-token ${logprobClass(token.logprob)} tooltip cursor-help`,
          dataset: { tip: formatLogprobTooltip(token) },
          text: token.token || ""
        })
      )
    }

    scroll.append(tokensEl)
    section.append(scroll)
    root.append(section)
  }

  // Queue Info (for queued runs)
  if (data.status === "queued") {
    const section = el("div", { className: "bg-info/10 border border-info/20 rounded-lg p-3 space-y-2" }, [
      sectionHeader("clock", "Queue Info", { colorClass: "text-info" })
    ])

    const body = el("div", { className: "space-y-1 text-sm" })
    if (data.run_after) {
      body.append(kvRow("Run After", formatTime(data.run_after), { labelClassName: "text-info/70" }))
    }
    if (data.expected_last_message_id) {
      body.append(
        kvRow(
          "Expected Last Message ID",
          el("span", { className: "font-mono", text: data.expected_last_message_id }),
          { labelClassName: "text-info/70" }
        )
      )
    }

    section.append(body)
    root.append(section)
  }

  return root
}
