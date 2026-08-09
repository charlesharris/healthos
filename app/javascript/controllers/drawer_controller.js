import { Controller } from "@hotwired/stimulus"

// Quick Review as a panel over the queue.
//
// HO §88: "Most Cases should be resolvable without opening the full
// Workbench." Triage is a run of small decisions, and a full page navigation
// per Case throws away the filter set and scroll position between each one.
//
// The panel is strictly an overlay on the same page — /ops/cases/:id remains
// a real, linkable, audited page and renders standalone when visited
// directly. Nothing here is required to reach or resolve a Case.
export default class extends Controller {
  static targets = ["panel", "frame"]

  connect() {
    this.returnFocusTo = null
  }

  // Fired by the frame itself once its content has been swapped in, so the
  // panel appears with the Case already rendered rather than empty.
  opened() {
    if (this.frameTarget.children.length === 0) return

    if (this.element.hidden) this.returnFocusTo = document.activeElement

    this.element.hidden = false
    // The queue narrows to make room rather than disappearing under the
    // panel, so the operator can see which row is next while working one.
    document.documentElement.classList.add("drawer-open")
    this.panelTarget.querySelector("[data-drawer-close]")?.focus()
  }

  close(event) {
    event?.preventDefault()
    if (this.element.hidden) return

    this.element.hidden = true
    document.documentElement.classList.remove("drawer-open")

    // Clearing the frame matters: without it, re-opening the same Case would
    // find the src unchanged and never fire another frame-load.
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""

    // The queue owns row selection; say the panel closed and let it decide.
    this.dispatch("closed")

    this.returnFocusTo?.focus()
    this.returnFocusTo = null
  }

  escape(event) {
    if (event.key === "Escape") this.close(event)
  }
}

// Deliberately no focus trap. This is a non-modal side panel: the queue beside
// it stays live so ↑/↓ can move to the next Case without closing anything,
// and trapping focus would break exactly the workflow the panel exists for.

