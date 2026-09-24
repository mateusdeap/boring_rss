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
//             pattern); Enter or → opens a feed; on a folder, Enter
//             toggles it, → expands, ← collapses (← on a feed inside a
//             folder moves to the folder)
//   M         mark / unmark the item under the cursor
//   U         unread-only filter    ⇧R  mark all read (current feed)
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

  // The item list names the tree row it belongs to (a feed, or the
  // Marked view) in #items[data-tree-row].
  feedNavigated(event) {
    const treeRowId = event.target.querySelector("#items")?.dataset.treeRow
    if (!treeRowId) return

    this.selected.feedRowId = treeRowId
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

  // keydown@document — page-wide single-key shortcuts. Letters are matched
  // case-insensitively with Shift as the only modifier ("shift+r"), not by
  // event.key's case: Caps Lock flips the case without Shift, which would
  // otherwise turn a plain R into "mark all read" and silence J/K/M/U.
  key(event) {
    if (this.ignored(event)) return

    switch (this.combo(event)) {
      case "j": return this.handled(event, () => this.moveItem(1))
      case "k": return this.handled(event, () => this.moveItem(-1))
      case "Enter":
        // Enter on a focused control keeps its own meaning.
        if (event.target.closest("a, button, summary")) return
        return this.openItemUnderCursor(event)
      case "m": return this.handled(event, () => this.toggleMark())
      case "u":
      case "shift+r":
        return this.clickShortcut(event, this.combo(event))
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

    const rows = this.visibleTreeRows()
    const index = rows.indexOf(row)
    const isFolder = "folderId" in row.dataset
    const expanded = row.getAttribute("aria-expanded") === "true"

    switch (event.key) {
      case "ArrowDown": return this.handled(event, () => rows[index + 1]?.focus())
      case "ArrowUp": return this.handled(event, () => rows[index - 1]?.focus())
      case "Home": return this.handled(event, () => rows[0]?.focus())
      case "End": return this.handled(event, () => rows.at(-1)?.focus())
      case "Enter":
        return this.handled(event, () => isFolder ? this.setFolderExpanded(row, !expanded) : row.querySelector("a")?.click())
      case "ArrowRight":
        if (!isFolder) return this.handled(event, () => row.querySelector("a")?.click())
        return this.handled(event, () => expanded ? rows[index + 1]?.focus() : this.setFolderExpanded(row, true))
      case "ArrowLeft":
        if (isFolder) return this.handled(event, () => this.setFolderExpanded(row, false))
        return this.handled(event, () => this.folderRow(row.dataset.parentFolder)?.focus())
    }
  }

  // click on a folder row.
  toggleFolder(event) {
    const row = event.currentTarget
    this.setFolderExpanded(row, row.getAttribute("aria-expanded") !== "true")
    row.focus()
  }

  // Updates the DOM immediately, then saves the state in the background
  // (FoldersController#update, JSON). Rows re-rendered later by a
  // broadcast read the saved state, so they come back hidden/shown to match.
  setFolderExpanded(row, expanded) {
    row.setAttribute("aria-expanded", expanded)
    row.querySelector("[data-disclosure]").textContent = expanded ? "▾" : "▸"
    this.element.querySelectorAll(`#feeds [data-parent-folder="${row.dataset.folderId}"]`).forEach((child) => {
      child.hidden = !expanded
    })
    if (!expanded && document.activeElement?.hidden) row.focus()

    fetch(`/folders/${row.dataset.folderId}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ folder: { collapsed: !expanded } })
    })
  }

  folderRow(folderId) {
    return folderId && this.element.querySelector(`#feeds [data-folder-id="${folderId}"]`)
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

  // M acts on the cursor row (J/K), else on the item open in the reader.
  // Items::MarksController answers with Turbo Streams for the row and the
  // reader's MARK button; render them here since this isn't a form submit.
  async toggleMark() {
    const readerId = this.element.querySelector("[data-item-id]")?.dataset.itemId
    const row = (this.selected.itemRowId && document.getElementById(this.selected.itemRowId)) ||
      (readerId && document.getElementById(`item_${readerId}`))
    if (!row?.dataset.markUrl) return

    const response = await fetch(row.dataset.markUrl, {
      method: row.dataset.marked === "true" ? "DELETE" : "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      }
    })
    if (response.ok) window.Turbo.renderStreamMessage(await response.text())
  }

  // Toolbar buttons that carry data-shortcut (feeds/show.html.erb). A
  // disabled one (e.g. "Mark all read — none unread") does nothing.
  clickShortcut(event, combo) {
    const control = this.element.querySelector(`[data-shortcut="${combo}"]`)
    if (control && !control.disabled) this.handled(event, () => control.click())
  }

  combo(event) {
    if (!/^[a-z]$/i.test(event.key)) return event.key
    const letter = event.key.toLowerCase()
    return event.shiftKey ? `shift+${letter}` : letter
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
  // (A selected feed inside a collapsed folder hands the tab stop to the
  // first visible row.)
  updateTreeTabStop() {
    const rows = this.treeRows()
    const visible = rows.filter((row) => !row.hidden)
    const stop = visible.find((row) => row.id === this.selected.feedRowId) || visible[0]
    rows.forEach((row) => { row.tabIndex = row === stop ? 0 : -1 })
  }

  treeRows() {
    return [...this.element.querySelectorAll("#feeds [role='treeitem']")]
  }

  visibleTreeRows() {
    return this.treeRows().filter((row) => !row.hidden)
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
