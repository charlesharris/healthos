import { Controller } from "@hotwired/stimulus"

// A filter form that submits when a control changes.
//
// Changing a filter is the intent; making the operator then press Apply is a
// second step that exists only because the form was built before the
// behaviour was.
//
// Everything here is enhancement. The submit button is real markup and works
// without JavaScript — it is hidden at runtime, not omitted from the DOM, so
// the form degrades to an ordinary GET.
export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.submitTargets.forEach((button) => { button.hidden = true })
  }

  submit() {
    this.element.requestSubmit()
  }
}
