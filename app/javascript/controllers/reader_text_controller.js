import { Controller } from "@hotwired/stimulus"
import { savePreferences } from "lib/preferences"

// The reader's TEXT bar ([T]): article text size (14–22px, 1px steps) and
// measure (60 / 68 / 76ch). One app-wide setting per user, saved to the
// database so it follows them across devices. Applied at once through the
// --reader-size / --reader-measure custom properties that every article
// size is derived from.
//
// Whether the bar is open survives moving to the next item: it's kept on
// the reader pane, which lives outside the current_item frame.
export default class extends Controller {
  static targets = ["bar", "toggle", "size", "smaller", "larger", "measure", "status"]
  static values = { size: Number, measure: Number }

  static MIN = 14
  static MAX = 22

  connect() {
    this.pane = this.element.closest(".rdr-pane-reader")
    this.setOpen(this.pane?.dataset.textOpen === "true")
    this.render()
  }

  toggle() {
    this.setOpen(this.barTarget.hidden)
  }

  setOpen(open) {
    this.barTarget.hidden = !open
    this.toggleTarget.setAttribute("aria-pressed", open)
    this.element.dataset.textOpen = open
    if (this.pane) this.pane.dataset.textOpen = open
  }

  smaller() { this.setSize(this.sizeValue - 1) }
  larger() { this.setSize(this.sizeValue + 1) }

  setSize(size) {
    const clamped = Math.min(Math.max(size, this.constructor.MIN), this.constructor.MAX)
    if (clamped === this.sizeValue) return

    this.sizeValue = clamped
    this.save({ reader_text_size: clamped })
  }

  measure(event) {
    const measure = Number(event.currentTarget.dataset.measure)
    if (measure === this.measureValue) return

    this.measureValue = measure
    this.save({ reader_measure: measure })
  }

  render() {
    this.element.style.setProperty("--reader-size", `${this.sizeValue}px`)
    this.element.style.setProperty("--reader-measure", `${this.measureValue}ch`)
    this.sizeTarget.textContent = `${this.sizeValue} px`
    this.smallerTarget.disabled = this.sizeValue <= this.constructor.MIN
    this.largerTarget.disabled = this.sizeValue >= this.constructor.MAX
    this.measureTargets.forEach((button) => {
      const measure = Number(button.dataset.measure)
      const current = measure === this.measureValue
      button.setAttribute("aria-pressed", current)
      button.textContent = current ? `${measure} ch` : measure
    })
  }

  async save(attributes) {
    this.render()
    this.dispatch("changed")
    this.statusTarget.textContent = "saving…"
    const saved = await savePreferences(attributes)
    this.statusTarget.textContent = saved ? "saved · all feeds" : "not saved — ERR"
  }
}
