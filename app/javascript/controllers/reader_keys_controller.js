import { Controller } from "@hotwired/stimulus"

// The reader's keyboard map (reading pane spec). Lives on the reader pane,
// outside the current_item frame, and drives the controllers inside it —
// through reader:* events on .rdr-reader, or by clicking the control the
// key is printed on (data-reader-key), so a key never does anything its
// button doesn't.
//
//   U   read / unread          V   open original ↗      /   find
//   N   next match  ⇧N  prev   T   text settings bar    I   details
//   SPACE / ⇧SPACE  page down / up in the article
//   C   copy the focused code block (else the first one in view)
//   R   poll now (only offered when nothing is unread)
//   ESC closes one layer per press: find bar, then text bar, then — under
//       1100px — back to the item list.
//
// J/K, M, ⇧U, ⇧R and the tree keys belong to selection_controller.js,
// which listens on window: this runs first (document) and anything handled
// here is preventDefault-ed, which selection skips.
//
// Letters are matched case-insensitively with Shift as an explicit
// modifier, never by event.key's case (Caps Lock flips it without Shift).
export default class extends Controller {
  key(event) {
    if (this.ignored(event)) return

    const reader = this.reader
    switch (this.combo(event)) {
      case "u": return this.click(event, "[data-reader-key='u']")
      case "v": return this.click(event, "[data-original-link]")
      case "r": return this.click(event, "[data-reader-key='r']")
      case "/": return reader && this.handled(event, () => this.emit("find-open"))
      case "t": return reader && this.handled(event, () => this.emit("text-toggle"))
      case "i": return reader && this.handled(event, () => this.emit("details-toggle"))
      case "n": return this.findOpen && this.handled(event, () => this.emit("find-next"))
      case "shift+n": return this.findOpen && this.handled(event, () => this.emit("find-prev"))
      case " ": return this.page(event, 1)
      case "shift+ ": return this.page(event, -1)
      case "c": return this.copyFocusedCode(event)
      case "Escape": return this.escape(event)
    }
  }

  escape(event) {
    if (this.findOpen) return this.handled(event, () => this.emit("find-close"))
    if (this.reader?.dataset.textOpen === "true") return this.handled(event, () => this.emit("text-toggle"))

    // Back to the items — only where the reader replaced them (< 1100px),
    // i.e. when a back link for the reader is actually on screen.
    const back = [...this.element.querySelectorAll("[data-reader-back='reader']")].find((link) => link.checkVisibility())
    if (back) this.handled(event, () => back.click())
  }

  page(event, direction) {
    // Space on a button or link keeps activating it.
    if (event.target.closest("a, button, summary")) return
    const scroller = this.reader?.querySelector(".rdr-reader-scroll")
    if (!scroller) return

    // A screenful less two lines, so the last lines stay in view.
    const lineHeight = parseFloat(getComputedStyle(scroller.querySelector(".r-body") || scroller).lineHeight) || 26
    this.handled(event, () => scroller.scrollBy({ top: direction * (scroller.clientHeight - 2 * lineHeight) }))
  }

  copyFocusedCode(event) {
    const block = document.activeElement?.closest(".r-codeblock") || this.firstCodeInView()
    if (block) this.handled(event, () => this.copy(block))
  }

  // click on a code block's [C] COPY.
  copyCode(event) {
    this.copy(event.currentTarget.closest(".r-codeblock"))
  }

  async copy(block) {
    const button = block.querySelector(".rdr-code-copy")
    const label = button.innerHTML
    try {
      await navigator.clipboard.writeText(block.querySelector("pre").innerText)
      button.textContent = "COPIED"
    } catch {
      button.textContent = "COPY FAILED"
    }
    setTimeout(() => { button.innerHTML = label }, 1500)
  }

  firstCodeInView() {
    const scroller = this.reader?.querySelector(".rdr-reader-scroll")
    if (!scroller) return null
    const view = scroller.getBoundingClientRect()
    return [...scroller.querySelectorAll(".r-codeblock")].find((block) => {
      const box = block.getBoundingClientRect()
      return box.bottom > view.top && box.top < view.bottom
    })
  }

  emit(name) {
    this.reader.dispatchEvent(new CustomEvent(`reader:${name}`))
  }

  click(event, selector) {
    const control = this.element.querySelector(selector)
    if (control && !control.disabled) this.handled(event, () => control.click())
  }

  get reader() {
    return this.element.querySelector(".rdr-reader[data-item-id]")
  }

  get findOpen() {
    return this.reader?.dataset.findOpen === "true"
  }

  combo(event) {
    if (!/^[a-z ]$/i.test(event.key)) return event.key
    const key = event.key.toLowerCase()
    return event.shiftKey ? `shift+${key}` : key
  }

  // Typing in a field (the find field handles its own Esc / Enter), a
  // modifier chord, or an open dialog is never a shortcut.
  ignored(event) {
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return true
    if (event.target.closest("input, textarea, select, [contenteditable]")) return true
    return document.querySelector("dialog[open]") !== null
  }

  handled(event, action) {
    event.preventDefault()
    action()
  }
}
