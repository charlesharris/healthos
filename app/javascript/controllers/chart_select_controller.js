import { Controller } from "@hotwired/stimulus"

// Drag a region on the distribution chart to compare it against everything
// outside it.
//
// The selection is a URL, not client state. Releasing the pointer navigates —
// so the view is linkable, back/forward work, the server recomputes the
// comparison from the same tenant-scoped query as any other request, and the
// read stays audited. A selection held only in JavaScript would be none of
// those things.
//
// Without JavaScript the chart still renders with the Signal's own window
// selected, and the from/to form underneath still works. This adds a faster
// way to do something that was already possible.
export default class extends Controller {
  static targets = ["surface", "rect", "readout", "form", "from", "to", "vmin", "vmax"]
  static values = {
    // Plot geometry in viewBox units, plus the data range it maps onto.
    left: Number, top: Number, width: Number, height: Number,
    startMs: Number, endMs: Number, valueMin: Number, valueMax: Number,
    // The URL the selection hangs off, handed over by the server rather than
    // read from window.location. Inside the drawer those are different things:
    // the address bar says /ops/cases while the panel is showing one Case, and
    // deriving the target from the address bar navigated the frame to the
    // queue and closed the panel.
    url: String,
    frame: String
  }

  connect() {
    this.dragging = null
  }

  start(event) {
    if (event.button !== 0) return

    const point = this.#point(event)
    if (point === null) return

    event.preventDefault()
    this.dragging = { origin: point, current: point }
    this.surfaceTarget.setPointerCapture(event.pointerId)
    this.#draw()
  }

  move(event) {
    if (!this.dragging) return

    this.dragging.current = this.#point(event, { clamp: true })
    this.#draw()
  }

  // A click that never moved is not a selection — it is how you dismiss one.
  finish(event) {
    if (!this.dragging) return

    const { origin, current } = this.dragging
    this.dragging = null
    this.surfaceTarget.releasePointerCapture?.(event.pointerId)

    const dx = Math.abs(current.x - origin.x)
    const dy = Math.abs(current.y - origin.y)
    if (dx < 6 && dy < 6) {
      this.#hide()
      return
    }

    const [x1, x2] = [origin.x, current.x].sort((a, b) => a - b)
    const [y1, y2] = [origin.y, current.y].sort((a, b) => a - b)

    const params = {
      from: new Date(this.#timeAt(x1)).toISOString(),
      to: new Date(this.#timeAt(x2)).toISOString()
    }

    // A drag spanning nearly the whole value axis means "this time range",
    // not "this box". Sending value bounds anyway would put a selected-on-the-
    // outcome warning on a selection that did not condition on the outcome.
    if (y2 - y1 < this.heightValue * 0.9) {
      params.vmin = this.#valueAt(y2).toFixed(2)
      params.vmax = this.#valueAt(y1).toFixed(2)
    }

    this.#visit(params)
  }

  cancel() {
    if (!this.dragging) return

    this.dragging = null
    this.#hide()
  }

  #visit(params) {
    const url = new URL(this.urlValue || window.location.href, window.location.origin)
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value))

    const frame = this.frameValue && document.getElementById(this.frameValue)
    if (frame) {
      frame.src = url.toString()
    } else {
      window.Turbo ? window.Turbo.visit(url.toString()) : (window.location.href = url.toString())
    }
  }

  #point(event, { clamp = false } = {}) {
    const box = this.surfaceTarget.getBoundingClientRect()
    const scale = this.widthValue / box.width

    let x = this.leftValue + (event.clientX - box.left) * scale
    let y = this.topValue + (event.clientY - box.top) * scale

    if (clamp) {
      x = Math.min(Math.max(x, this.leftValue), this.leftValue + this.widthValue)
      y = Math.min(Math.max(y, this.topValue), this.topValue + this.heightValue)
    } else if (x < this.leftValue || x > this.leftValue + this.widthValue ||
               y < this.topValue || y > this.topValue + this.heightValue) {
      return null
    }

    return { x, y }
  }

  #timeAt(x) {
    const fraction = (x - this.leftValue) / this.widthValue
    return this.startMsValue + fraction * (this.endMsValue - this.startMsValue)
  }

  #valueAt(y) {
    const fraction = (this.topValue + this.heightValue - y) / this.heightValue
    return this.valueMinValue + fraction * (this.valueMaxValue - this.valueMinValue)
  }

  #draw() {
    const { origin, current } = this.dragging
    const [x1, x2] = [origin.x, current.x].sort((a, b) => a - b)
    const [y1, y2] = [origin.y, current.y].sort((a, b) => a - b)

    this.rectTarget.setAttribute("x", x1)
    this.rectTarget.setAttribute("y", y1)
    this.rectTarget.setAttribute("width", Math.max(x2 - x1, 0))
    this.rectTarget.setAttribute("height", Math.max(y2 - y1, 0))
    this.rectTarget.removeAttribute("hidden")

    if (this.hasReadoutTarget) {
      const from = new Date(this.#timeAt(x1))
      const to = new Date(this.#timeAt(x2))
      const day = { month: "short", day: "numeric" }
      const span = `${from.toLocaleDateString(undefined, day)} – ${to.toLocaleDateString(undefined, day)}`
      const values = y2 - y1 < this.heightValue * 0.9
        ? ` · ${this.#valueAt(y2).toFixed(0)}–${this.#valueAt(y1).toFixed(0)}`
        : ""

      this.readoutTarget.textContent = `${span}${values}`
      this.readoutTarget.removeAttribute("hidden")
    }
  }

  #hide() {
    this.rectTarget.setAttribute("hidden", "")
    if (this.hasReadoutTarget) this.readoutTarget.setAttribute("hidden", "")
  }
}
