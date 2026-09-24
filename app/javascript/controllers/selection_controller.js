import { Controller } from "@hotwired/stimulus"

// Tracks which FeedTree row / ItemTable row is selected and which pane last
// had focus: selection is what you're looking at (aria-selected, paper-3
// fill), focus is where the keys go (is-focused, RDR-01's 2px ink bar —
// only on the focused pane's row). Keyed off real frame navigation, not
// clicks, so clicking dead space in a row never marks it selected without
// the pane actually changing.
//
// Also owns `data-reading` on the pane grid: under 1100px the reader
// replaces the item table (see .rdr-panes in application.css), so opening
// an item sets it and the reader's BACK button (or Esc) clears it.
//
// Keyboard (RDR-01: shortcuts are printed on the controls they trigger;
// the full list is the KEYS dialog in feeds/index.html.erb):
//   J / K     move the item cursor; Enter opens the item under it
//   ↑ / ↓     move within the feed tree (roving tabindex, WAI-ARIA tree
//             pattern); Enter or → opens the feed
//   A         add feed        L  toggle the fetch log
//   O         open the current item's original page
//   ?         show all keys   Esc  back to items (narrow layout)
// J/K move a cursor rather than open, so skimming never marks items read —
// only opening does (Item#mark_read!).
export default class extends Controller {
  connect() {
    this.selected = { feedRowId: null, itemRowId: null, focusedPane: null }

    // Item/feed rows get replaced live by Turbo Stream broadcasts (e.g.
    // Item#mark_read! re-rendering the very row you just selected), which
    // would otherwise wipe the attributes applied below. Re-apply right
    // after each stream renders.
    this.wrapStreamRender = (event) => {
      const render = event.detail.render
      event.detail.render = (streamElement) => {
        render(streamElement)
        this.applySelection()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.wrapStreamRender)
    this.applySelection()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.wrapStreamRender)
  }

  feedNavigated(event) {
    const feedId = event.target.querySelector("#items")?.dataset.feedId
    if (!feedId) return

    this.selected.feedRowId = `feed_${feedId}`
    this.selected.focusedPane = "tree"
    this.element.dataset.reading = "false"
    this.applySelection()
  }

  itemNavigated(event) {
    const itemId = event.target.querySelector("[data-item-id]")?.dataset.itemId
    if (!itemId) return

    this.selected.itemRowId = `item_${itemId}`
    this.selected.focusedPane = "items"
    this.element.dataset.reading = "true"
    this.applySelection()
  }

  back() {
    this.element.dataset.reading = "false"
  }

  // keydown@document — page-wide single-key shortcuts.
  key(event) {
    if (this.ignored(event)) return

    switch (event.key) {
      case "j": return this.handled(event, () => this.moveItem(1))
      case "k": return this.handled(event, () => this.moveItem(-1))
      case "Enter":
        // Enter on a focused control keeps its own meaning.
        if (event.target.closest("a, button, summary")) return
        return this.openItemUnderCursor(event)
      case "a": return this.handled(event, () => document.getElementById("add-feed-dialog")?.showModal())
      case "l": return this.handled(event, () => this.toggleLog())
      case "o": return this.handled(event, () => this.element.querySelector("[data-original-link]")?.click())
      case "?": return this.handled(event, () => document.getElementById("keys-dialog")?.showModal())
      case "Escape": return this.back()
    }
  }

  // keydown on the tree itself — arrow keys only mean "move" while focus
  // is inside it, so they keep scrolling panes everywhere else.
  treeKey(event) {
    const row = event.target.closest("[role='treeitem']")
    if (!row) return

    const rows = this.treeRows()
    const index = rows.indexOf(row)

    switch (event.key) {
      case "ArrowDown": return this.handled(event, () => rows[index + 1]?.focus())
      case "ArrowUp": return this.handled(event, () => rows[index - 1]?.focus())
      case "Home": return this.handled(event, () => rows[0]?.focus())
      case "End": return this.handled(event, () => rows.at(-1)?.focus())
      case "Enter":
      case "ArrowRight":
        return this.handled(event, () => row.querySelector("a")?.click())
    }
  }

  moveItem(delta) {
    const rows = [...this.element.querySelectorAll("#items > tr")]
    if (rows.length === 0) return

    const current = rows.findIndex((row) => row.id === this.selected.itemRowId)
    const next = current === -1 ? 0 : Math.min(Math.max(current + delta, 0), rows.length - 1)

    this.selected.itemRowId = rows[next].id
    this.selected.focusedPane = "items"
    // Keys now belong to the item table: take DOM focus out of the tree so
    // a following Enter opens the item, not the focused feed row.
    if (document.activeElement?.closest("#feeds")) document.activeElement.blur()
    this.applySelection()
    rows[next].scrollIntoView({ block: "nearest" })
  }

  openItemUnderCursor(event) {
    if (this.selected.focusedPane !== "items" || !this.selected.itemRowId) return

    const link = document.getElementById(this.selected.itemRowId)?.querySelector("a")
    if (link) this.handled(event, () => link.click())
  }

  toggleLog() {
    const log = this.element.querySelector(".rdr-log")
    if (log) log.open = !log.open
  }

  applySelection() {
    this.element.querySelectorAll("[aria-selected='true']").forEach((el) => {
      el.setAttribute("aria-selected", "false")
      el.classList.remove("is-focused")
    })

    this.select(this.selected.feedRowId, this.selected.focusedPane === "tree")
    this.select(this.selected.itemRowId, this.selected.focusedPane === "items")
    this.updateTreeTabStop()
  }

  select(rowId, focused) {
    const row = rowId && document.getElementById(rowId)
    if (!row) return

    row.setAttribute("aria-selected", "true")
    row.classList.toggle("is-focused", focused)
  }

  // Roving tabindex: exactly one tree row (the selected one, else the
  // first) is reachable with Tab; arrows move from there.
  updateTreeTabStop() {
    const rows = this.treeRows()
    const stop = rows.find((row) => row.id === this.selected.feedRowId) || rows[0]
    rows.forEach((row) => { row.tabIndex = row === stop ? 0 : -1 })
  }

  treeRows() {
    return [...this.element.querySelectorAll("#feeds [role='treeitem']")]
  }

  // Typing in a field, a modifier chord, or an open dialog (which handles
  // its own Esc) is never a shortcut.
  ignored(event) {
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return true
    if (event.target.closest("input, textarea, select, [contenteditable]")) return true
    if (event.target.closest("#feeds") && event.key === "Enter") return true
    return document.querySelector("dialog[open]") !== null
  }

  handled(event, action) {
    event.preventDefault()
    action()
  }
}
