import { Controller } from "@hotwired/stimulus"

// The Ops Queue: filter behaviour and keyboard triage.
//
// Everything here is enhancement. Without JavaScript the filter bar is an
// ordinary GET form with a visible Apply button, and every row is an ordinary
// link — which is why the Apply button is hidden here, at runtime, rather
// than omitted from the markup.
export default class extends Controller {
  static targets = ["form", "apply", "row"]
  static values = { currentCase: String }

  connect() {
    if (this.hasApplyTarget) this.applyTarget.hidden = true
  }

  // Acting on a Case from the drawer replaces its row via Turbo stream, and
  // the replacement arrives without the selection class — the server has no
  // idea which row the operator is looking at. Re-applying it as the new row
  // connects keeps the panel and the row behind it pointing at each other.
  rowTargetConnected(row) {
    if (this.currentCaseValue && row.dataset.caseId === this.currentCaseValue) {
      row.classList.add("is-current")
    }
  }

  // Changing a filter is the intent; making the operator then press Apply is
  // a second step that exists only because the form was built before the
  // behaviour was.
  applyFilters() {
    this.formTarget.requestSubmit()
  }

  // The whole row is a click target, but only where a click means "open this
  // Case". Clicks that land on the inline assign/triage controls are theirs.
  activate(event) {
    if (event.target.closest("a, button, select, input, form, label")) return

    const link = event.currentTarget.querySelector("[data-queue-target='title']")
    if (link) link.click()
  }

  select(event) {
    this.currentCaseValue = event.target.closest(".qrow")?.dataset.caseId || ""
    this.markCurrent()
  }

  clearCurrent() {
    this.currentCaseValue = ""
    this.markCurrent()
  }

  markCurrent() {
    this.rowTargets.forEach((row) =>
      row.classList.toggle("is-current", Boolean(this.currentCaseValue) && row.dataset.caseId === this.currentCaseValue)
    )
  }

  // ↑/↓ and j/k move between rows; Enter opens, because the row title is a
  // real link and already has focus. Ignored while typing in a filter.
  navigate(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.closest("input, select, textarea")) return

    const step = { ArrowDown: 1, j: 1, ArrowUp: -1, k: -1 }[event.key]
    if (!step) return

    const titles = this.rowTargets.map((row) => row.querySelector("[data-queue-target='title']"))
    if (titles.length === 0) return

    const current = titles.indexOf(document.activeElement)
    const next = current === -1 ? (step > 0 ? 0 : titles.length - 1) : current + step

    if (next < 0 || next >= titles.length) return

    event.preventDefault()
    titles[next].focus()
    titles[next].scrollIntoView({ block: "nearest" })
  }
}
