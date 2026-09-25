import { Controller } from "@hotwired/stimulus"
import { savePreferences } from "lib/preferences"

// Tracks which FeedTree row / ItemTable row is selected and which pane last
// had focus: selection is what you're looking at (aria-selected, paper-3
// fill), focus is where the keys go (is-focused, RDR-01's 2px ink bar —
// only on the focused pane's row). Keyed off real frame navigation, not
// clicks, so clicking dead space in a row never marks it selected without
// the pane actually changing.
//
// Also owns `data-screen` on the pane grid (feeds / items / reader): which
// pane is in front where they don't all fit (see .rdr-panes in
// application.css). A feed loading shows the items, an item loading shows
// the reader; the back links (ESC ← 02 ITEMS, ← ITEMS, ← FEEDS) are real
// links, so every screen has its own URL. On phones a swipe from the left
// edge follows the screen's back link.
//
// Keyboard (RDR-01: shortcuts are printed on the controls they trigger;
// the full list is the KEYS dialog in feeds/_keys.html.erb). Listens on
// window, after reader_keys_controller.js (document), which owns the
// reader's keys — U, V, /, N, T, I, Space, C, R and Esc:
//   J / K     open the next / previous item (reading pane spec: the
//             reader's [J] NEXT / [K] PREV); with nothing open, J opens
//             the first unread. Opening marks the item read; U undoes it.
//   ↑ / ↓     move within the feed tree (roving tabindex, WAI-ARIA tree
//             pattern); Enter or → opens a feed; on a folder, Enter
//             toggles it, → expands, ← collapses (← on a feed inside a
//             folder moves to the folder)
//   G / F     left pane: Groups or Feeds mode (saved per user)
//   M         mark / unmark the open item
//   ⇧U        unread-only filter    ⇧R  mark all read (current feed)
//   A         add feed        L  toggle the fetch log
//   ?         show all keys
export default class extends Controller {
  connect() {
    // A full page load (an item's or feed's own URL) arrives with its
    // panes already filled in; pick the selection up from them.
    this.selected = {
      feedRowId: this.element.querySelector("#items")?.dataset.treeRow || null,
      itemRowId: this.openItemId ? `item_${this.openItemId}` : null,
      focusedPane: this.openItemId ? "items" : null
    }

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
    // Opening a group shows Groups mode, opening a feed (a group's health
    // link, say) shows Feeds mode: the selected row is always on screen.
    const list = document.getElementById(treeRowId)?.closest("#groups, #feeds")
    if (list) this.setMode(list.id)
    this.element.dataset.screen = "items"
    this.applySelection()
  }

  itemNavigated(event) {
    const itemId = event.target.querySelector("[data-item-id]")?.dataset.itemId
    if (!itemId) return

    this.selected.itemRowId = `item_${itemId}`
    this.selected.focusedPane = "items"
    this.element.dataset.screen = "reader"
    this.applySelection()
    event.target.querySelector(".rdr-reader-scroll")?.focus({ preventScroll: true })
  }

  // The [G] GROUPS / [F] FEEDS control and keys. The switch happens here;
  // the choice is saved in the background.
  showGroups() { this.setMode("groups") }
  showFeeds() { this.setMode("feeds") }

  setMode(mode) {
    const pane = this.element.querySelector(".rdr-pane-tree")
    if (!pane || pane.dataset.treeMode === mode) return

    pane.dataset.treeMode = mode
    pane.querySelectorAll("[data-tree-mode-button]").forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.treeModeButton === mode)
    })
    this.updateTreeTabStop()
    savePreferences({ tree_mode: mode })
  }

  get treeMode() {
    return this.element.querySelector(".rdr-pane-tree")?.dataset.treeMode || "feeds"
  }

  // The reader's [K] PREV / [J] NEXT and the phone bottom bar.
  prev() { this.openAdjacent(-1) }
  next() { this.openAdjacent(1) }
  markCurrent() { this.toggleMark() }

  // Phone: a swipe from the left edge goes back one screen, like the
  // screen's own back link.
  swipeStart(event) {
    const touch = event.touches[0]
    this.swipe = touch.clientX < 24 ? { x: touch.clientX, y: touch.clientY } : null
  }

  swipeEnd(event) {
    if (!this.swipe) return
    const touch = event.changedTouches[0]
    const dx = touch.clientX - this.swipe.x
    const dy = Math.abs(touch.clientY - this.swipe.y)
    this.swipe = null
    if (dx < 80 || dy > dx / 2) return

    const back = [...this.element.querySelectorAll(`[data-reader-back='${this.element.dataset.screen}']`)]
      .find((link) => link.checkVisibility())
    back?.click()
  }

  // keydown@document — page-wide single-key shortcuts. Letters are matched
  // case-insensitively with Shift as the only modifier ("shift+r"), not by
  // event.key's case: Caps Lock flips the case without Shift, which would
  // otherwise turn a plain R into "mark all read" and silence J/K/M/U.
  key(event) {
    if (this.ignored(event)) return

    switch (this.combo(event)) {
      case "j": return this.handled(event, () => this.openAdjacent(1))
      case "k": return this.handled(event, () => this.openAdjacent(-1))
      case "Enter":
        // Enter on a focused control keeps its own meaning.
        if (event.target.closest("a, button, summary")) return
        return this.openItemUnderCursor(event)
      case "m": return this.handled(event, () => this.toggleMark())
      case "g": return this.handled(event, () => this.setMode("groups"))
      case "f": return this.handled(event, () => this.setMode("feeds"))
      case "shift+u":
      case "shift+r":
        return this.clickShortcut(event, this.combo(event))
      case "a": return this.handled(event, () => document.getElementById("add-feed-dialog")?.showModal())
      case "l": return this.handled(event, () => this.toggleLog())
      case "?": return this.handled(event, () => document.getElementById("keys-dialog")?.showModal())
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

  // Opens the item after / before the open one in the list. With nothing
  // open, J starts at the first unread row — or, with no list loaded, the
  // reader's [J] OPEN FIRST UNREAD (newest unread across all feeds).
  openAdjacent(delta) {
    const rows = [...this.element.querySelectorAll("#items > tr")]
    const current = rows.findIndex((row) => row.id === this.selected.itemRowId)
    let next

    if (current === -1) {
      if (delta < 0) return
      next = rows.find((row) => row.classList.contains("is-unread")) || rows[0]
      if (!next) return this.element.querySelector("[data-open-first-unread]")?.click()
    } else {
      next = rows[current + delta]
      if (!next) return
    }

    this.selected.itemRowId = next.id
    this.selected.focusedPane = "items"
    // Keys now belong to the items: take DOM focus out of the tree so a
    // following Enter doesn't open the focused feed row.
    if (document.activeElement?.closest("#feeds")) document.activeElement.blur()
    this.applySelection()
    next.scrollIntoView({ block: "nearest" })
    next.querySelector("a")?.click()
  }

  openItemUnderCursor(event) {
    if (this.selected.focusedPane !== "items" || !this.selected.itemRowId) return

    const link = document.getElementById(this.selected.itemRowId)?.querySelector("a")
    if (link) this.handled(event, () => link.click())
  }

  // M acts on the selected row (the open item). Items::MarksController
  // answers with Turbo Streams for the row and the reader's MARK button;
  // render them here since this isn't a form submit. Without the row (the
  // item's feed isn't the list shown), the reader's own MARK button does it.
  async toggleMark() {
    const row = this.selected.itemRowId && document.getElementById(this.selected.itemRowId)
    if (!row?.dataset.markUrl) {
      return this.element.querySelector(`#mark_item_${this.openItemId} button`)?.click()
    }

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
    this.updateReaderPosition()
  }

  // The reader header's "ITEM 3 / 7 · 5 unread" (wide) and "Field Notes ·
  // 3 / 7" (narrow, phone), from the list on screen; and its back links,
  // which return to that list (a feed or the Marked view) rather than
  // always the item's own feed.
  updateReaderPosition() {
    const reader = this.element.querySelector(".rdr-reader[data-item-id]")
    if (!reader) return

    const rows = [...this.element.querySelectorAll("#items > tr")]
    const row = document.getElementById(`item_${reader.dataset.itemId}`)
    const index = rows.indexOf(row)
    if (index !== -1) {
      const unread = rows.filter((tr) => tr.classList.contains("is-unread")).length
      const feed = row.querySelector(".r-feed")?.textContent.trim()
      reader.querySelectorAll("[data-reader-position='wide']").forEach((el) => {
        el.textContent = `ITEM ${index + 1} / ${rows.length} · ${unread} unread`
      })
      reader.querySelectorAll("[data-reader-position='narrow']").forEach((el) => {
        el.textContent = `${feed} · ${index + 1} / ${rows.length}`
      })
    }

    const listUrl = this.element.querySelector("#current_feed")?.getAttribute("src")
    if (listUrl) reader.querySelectorAll("[data-reader-back='reader']").forEach((link) => { link.href = listUrl })
  }

  get openItemId() {
    return this.element.querySelector(".rdr-reader[data-item-id]")?.dataset.itemId
  }

  select(rowId, focused) {
    const row = rowId && document.getElementById(rowId)
    if (!row) return

    row.setAttribute("aria-selected", "true")
    row.classList.toggle("is-focused", focused)
  }

  // Roving tabindex: exactly one tree row (the selected one, else the
  // first) is reachable with Tab; arrows move from there. Only the current
  // mode's list and the Marked row count.
  // (A selected feed inside a collapsed folder hands the tab stop to the
  // first visible row.)
  updateTreeTabStop() {
    const visible = this.visibleTreeRows()
    const stop = visible.find((row) => row.id === this.selected.feedRowId) || visible[0]
    this.element.querySelectorAll(".rdr-pane-tree [role='treeitem']").forEach((row) => { row.tabIndex = row === stop ? 0 : -1 })
  }

  treeRows() {
    return [...this.element.querySelectorAll(`#${this.treeMode} [role='treeitem'], .rdr-marked-list [role='treeitem']`)]
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
