const VIEWPORT_RENDER_MARGIN_PX = 800

const VISIBILITY_CALLBACKS = new WeakMap()
let viewportObserver = null

function getViewportObserver() {
  if (viewportObserver) return viewportObserver

  viewportObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue

      const callback = VISIBILITY_CALLBACKS.get(entry.target)
      if (!callback) continue

      callback()
    }
  }, {
    root: null,
    rootMargin: `${VIEWPORT_RENDER_MARGIN_PX}px 0px`,
    threshold: 0
  })

  return viewportObserver
}

export function isNearViewport(element) {
  try {
    const rect = element.getBoundingClientRect()
    return rect.bottom >= -VIEWPORT_RENDER_MARGIN_PX && rect.top <= window.innerHeight + VIEWPORT_RENDER_MARGIN_PX
  } catch {
    return true
  }
}

export function observeVisibility(element, callback) {
  VISIBILITY_CALLBACKS.set(element, callback)
  getViewportObserver().observe(element)

  return () => {
    VISIBILITY_CALLBACKS.delete(element)
    viewportObserver?.unobserve(element)
  }
}
