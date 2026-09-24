import { Controller } from "@hotwired/stimulus"

// Tracks which SidebarItem/TimelineRow is selected and which pane last had
// focus (design system section 07: selection is what you're looking at,
// focus is where the keys go — only the focused pane paints in accent).
// Keyed off real frame navigation, not clicks, so clicking dead space in a
// row never marks it selected without the pane actually changing.
export default class extends Controller {
  connect() {
    this.selected = { feedRowId: null, itemRowId: null, focusedPane: null }

    // Item/feed rows get replaced live by Turbo Stream broadcasts (e.g.
    // Item#mark_read! re-rendering the very row you just selected), which
    // would otherwise wipe the classes applied below. Re-apply right after
    // each stream renders.
    this.wrapStreamRender = (event) => {
      const render = event.detail.render
      event.detail.render = (streamElement) => {
        render(streamElement)
        this.applySelection()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.wrapStreamRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.wrapStreamRender)
  }

  feedNavigated(event) {
    const feedId = event.target.querySelector("#items")?.dataset.feedId
    if (!feedId) return

    this.selected.feedRowId = `feed_${feedId}`
    this.selected.focusedPane = "sidebar"
    this.applySelection()
  }

  itemNavigated(event) {
    const itemRow = event.target.querySelector("article[id^='item_']")
    if (!itemRow) return

    this.selected.itemRowId = itemRow.id
    this.selected.focusedPane = "list"
    this.applySelection()
  }

  applySelection() {
    this.element.querySelectorAll(".is-selected").forEach((el) => el.classList.remove("is-selected", "is-focused"))

    if (this.selected.feedRowId) {
      const feedRow = document.getElementById(this.selected.feedRowId)
      if (feedRow) {
        feedRow.classList.add("is-selected")
        if (this.selected.focusedPane === "sidebar") feedRow.classList.add("is-focused")
      }
    }

    if (this.selected.itemRowId) {
      const itemRow = document.getElementById(this.selected.itemRowId)
      if (itemRow) {
        itemRow.classList.add("is-selected")
        if (this.selected.focusedPane === "list") itemRow.classList.add("is-focused")
      }
    }
  }
}
