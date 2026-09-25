import { Controller } from "@hotwired/stimulus"
import { savePreferences } from "lib/preferences"

// The reader's details block ([I]): expanded, or collapsed to one line
// (with the byline moving under the title). One app-wide setting per user,
// expanded by default; the choice is saved and every later item opens the
// same way. The CSS keys off data-details-expanded.
export default class extends Controller {
  toggle() {
    const expanded = this.element.dataset.detailsExpanded !== "true"
    this.element.dataset.detailsExpanded = expanded
    this.dispatch("changed")
    savePreferences({ reader_details_expanded: expanded })
  }
}
