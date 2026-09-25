import { Controller } from "@hotwired/stimulus"

// The reader's loading state: text, never a spinner (RDR-01), and only
// when an item takes more than 150ms — faster loads paint straight to the
// article. The pane swaps its frame for the loading panel while
// data-loading is set; J / K keep working, and a newer request simply
// replaces the one in flight.
export default class extends Controller {
  static targets = ["panel", "header", "title", "request"]
  static DELAY = 150

  start(event) {
    if (event.target.id !== "current_item") return

    clearTimeout(this.timer)
    const url = new URL(event.detail.url)
    this.timer = setTimeout(() => this.show(url), this.constructor.DELAY)
  }

  stop() {
    clearTimeout(this.timer)
    delete this.element.dataset.loading
    this.panelTarget.hidden = true
  }

  show(url) {
    const itemId = url.pathname.match(/\/items\/(\d+)/)?.[1]
    const rows = [...document.querySelectorAll("#items > tr:not(.r-feedhead)")]
    const row = rows.find((tr) => tr.id === `item_${itemId}`)
    const position = row ? `${rows.indexOf(row) + 1} / ${rows.length}` : ""
    const feed = row?.querySelector(".r-feed")?.textContent.trim()

    this.headerTarget.textContent = `LOADING ${position}…`.replace("  ", " ")
    this.titleTarget.textContent = ["LOADING item", position.split(" /")[0], feed && `· ${feed}`].filter(Boolean).join(" ")
    this.requestTarget.textContent = `GET ${url.pathname}`
    this.element.dataset.loading = "true"
    this.panelTarget.hidden = false
  }
}
