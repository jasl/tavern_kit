import { escapeHtml } from "../../dom_helpers"

export function statusBadgeClass(status) {
  const classes = {
    succeeded: "badge-success",
    failed: "badge-error",
    canceled: "badge-warning",
    running: "badge-info",
    queued: "badge-ghost"
  }
  return classes[status] || "badge-ghost"
}

export function formatTime(timestamp) {
  if (!timestamp) return "-"
  const date = new Date(timestamp)
  return date.toLocaleString()
}

export function calculateDuration(start, end) {
  if (!start || !end) return "-"
  const ms = new Date(end) - new Date(start)
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(2)}s`
}

export function formatNumber(num) {
  if (num === undefined || num === null) return "-"
  return num.toLocaleString()
}

export function capitalizeFirst(str) {
  if (!str) return ""
  return str.charAt(0).toUpperCase() + str.slice(1)
}

export function roleClass(role) {
  const classes = {
    system: "bg-warning/10 border-warning/30",
    assistant: "bg-secondary/10 border-secondary/30",
    user: "bg-primary/10 border-primary/30"
  }
  return classes[role] || "bg-base-200 border-base-300"
}

export function roleBadgeClass(role) {
  const classes = {
    system: "badge-warning",
    assistant: "badge-secondary",
    user: "badge-primary"
  }
  return classes[role] || "badge-ghost"
}

export function logprobClass(logprob) {
  if (logprob === undefined || logprob === null) return ""
  if (logprob > -0.1) return "prob-very-high"
  if (logprob > -0.5) return "prob-high"
  if (logprob > -1.0) return "prob-medium"
  if (logprob > -2.0) return "prob-low"
  return "prob-very-low"
}

export function formatLogprobTooltip(tokenData) {
  if (!tokenData) return ""
  const prob = tokenData.logprob !== undefined
    ? `${(Math.exp(tokenData.logprob) * 100).toFixed(1)}%`
    : "N/A"

  let tooltip = `Prob: ${prob}`

  if (tokenData.top_logprobs && Array.isArray(tokenData.top_logprobs)) {
    const alts = tokenData.top_logprobs
      .slice(0, 3)
      .map(alt => `${escapeHtml(alt.token)}: ${(Math.exp(alt.logprob) * 100).toFixed(1)}%`)
      .join(", ")
    if (alts) {
      tooltip += ` | Alts: ${alts}`
    }
  }

  return tooltip
}
