import { Controller } from "@hotwired/stimulus"

// Dropdown for the top bar's organization switcher and account menu.
//
// Closes on outside click, on Escape, and on Turbo navigation — the last one
// matters because Turbo keeps the <body> across page loads, so a menu left
// open would survive a navigation it has nothing to do with.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.closeOnOutside = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.closeOnEscape = (event) => {
      if (event.key === "Escape") this.close()
    }
    this.closeOnVisit = () => this.close()

    document.addEventListener("click", this.closeOnOutside)
    document.addEventListener("keydown", this.closeOnEscape)
    document.addEventListener("turbo:before-visit", this.closeOnVisit)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
    document.removeEventListener("turbo:before-visit", this.closeOnVisit)
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (this.panelTarget.hidden) return

    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }
}
