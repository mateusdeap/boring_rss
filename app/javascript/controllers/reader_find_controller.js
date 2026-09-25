import { Controller } from "@hotwired/stimulus"

// The reader's FIND bar ([/]): case-insensitive plain-text search in the
// open article only, client-side. Hits are wrapped in <mark class="rdr-hit">
// (RDR-01's `mark` token); the current one also gets an ink outline.
// N / ⇧N (reader_keys_controller.js) or Enter / ⇧Enter in the field cycle
// through them. The bar lives inside the current_item frame, so the query
// clears whenever the item changes.
export default class extends Controller {
  static targets = ["bar", "toggle", "input", "count", "article"]

  connect() {
    this.hits = []
    this.current = -1
  }

  toggle() {
    this.barTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.barTarget.hidden = false
    this.toggleTarget.setAttribute("aria-pressed", "true")
    this.element.dataset.findOpen = "true"
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  close() {
    this.clear()
    this.inputTarget.value = ""
    this.countTarget.textContent = ""
    this.barTarget.hidden = true
    this.toggleTarget.setAttribute("aria-pressed", "false")
    this.element.dataset.findOpen = "false"
    if (this.element.contains(document.activeElement)) document.activeElement.blur()
  }

  // Only Esc, Enter and ⇧Enter mean anything inside the field.
  inputKey(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      event.shiftKey ? this.prev() : this.next()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  search() {
    this.clear()
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query) this.highlight(query)

    this.current = this.hits.length ? 0 : -1
    this.show()
  }

  next() { this.step(1) }
  prev() { this.step(-1) }

  step(delta) {
    if (!this.hits.length) return
    this.current = (this.current + delta + this.hits.length) % this.hits.length
    this.show()
  }

  show() {
    this.hits.forEach((hit, index) => hit.classList.toggle("is-current", index === this.current))
    const query = this.inputTarget.value.trim()
    this.countTarget.textContent = query ? `${this.hits.length ? this.current + 1 : 0} / ${this.hits.length}` : ""
    this.hits[this.current]?.scrollIntoView({ block: "center" })
  }

  highlight(query) {
    const walker = document.createTreeWalker(this.articleTarget, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => node.parentElement.closest("button, .r-codeblock-bar")
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT
    })
    const nodes = []
    while (walker.nextNode()) nodes.push(walker.currentNode)

    nodes.forEach((node) => {
      let text = node
      let index
      while (text && (index = text.data.toLowerCase().indexOf(query)) !== -1) {
        const match = text.splitText(index)
        text = match.splitText(query.length)
        const hit = document.createElement("mark")
        hit.className = "rdr-hit"
        match.replaceWith(hit)
        hit.append(match)
        this.hits.push(hit)
      }
    })
  }

  clear() {
    this.hits.forEach((hit) => {
      const parent = hit.parentNode
      hit.replaceWith(...hit.childNodes)
      parent?.normalize()
    })
    this.hits = []
    this.current = -1
  }
}
