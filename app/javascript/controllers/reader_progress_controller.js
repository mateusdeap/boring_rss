import { Controller } from "@hotwired/stimulus"

// The reader's status line: how far through the article you are and
// roughly how long is left (the item's word count at 200 wpm, scaled by
// what's still below the fold). At the end of an excerpt it points at the
// next item instead.
export default class extends Controller {
  static targets = ["scroller", "position", "inlineLeft", "hint", "left"]
  static values = { minutes: Number, kind: String }

  // Re-measured whenever the scroller or the article changes size — not
  // just on connect: the item can load while the reader pane is still
  // hidden (under 1100px the list is in front until it opens), and images
  // and fonts grow the article after it's drawn.
  connect() {
    this.hintHTML = this.hintTarget.innerHTML
    this.observer = new ResizeObserver(() => this.update())
    this.observer.observe(this.scrollerTarget)
    if (this.scrollerTarget.firstElementChild) this.observer.observe(this.scrollerTarget.firstElementChild)
    this.update()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  update() {
    if (this.kindValue === "empty") {
      this.positionTarget.textContent = "POS —"
      this.inlineLeftTarget.textContent = ""
      this.leftTarget.textContent = ""
      return
    }

    const scroller = this.scrollerTarget
    const max = scroller.scrollHeight - scroller.clientHeight
    const fraction = max <= 0 ? 1 : Math.min(scroller.scrollTop / max, 1)
    const percent = Math.round(fraction * 100)
    const minutesLeft = Math.round(this.minutesValue * (1 - fraction))
    const atExcerptEnd = this.kindValue === "excerpt" && percent >= 99

    const left = atExcerptEnd ? "excerpt end" : (this.minutesValue > 0 ? `~${minutesLeft} min left` : "")
    // Wide: "POS 34% · ~4 min left" on the left, key hints on the right.
    // Phone: "POS 34%" left, "~4 min left" right (CSS picks the spans).
    this.positionTarget.textContent = `POS ${percent}%`
    this.inlineLeftTarget.textContent = left ? ` · ${left}` : ""
    this.leftTarget.textContent = left

    this.hintTarget.innerHTML = atExcerptEnd
      ? `<span class="r-key">J</span> next item · read on open`
      : this.hintHTML
  }
}
