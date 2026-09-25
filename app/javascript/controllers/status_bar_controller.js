import { Controller } from "@hotwired/stimulus"

// Keeps the StatusBar's FEEDS / UNREAD / LAST FETCH / ERR / STALE cells,
// and the left pane header's feed and unread counts, in step
// with the feed tree (#feeds). Each tree row carries data-unread,
// data-health and data-fetched-at, and rows are appended/replaced/removed
// live by Turbo Streams, so observing the tree is enough — the bar never
// needs its own broadcast.
export default class extends Controller {
  static targets = ["feeds", "unread", "last", "errors", "stale"]

  connect() {
    this.tree = document.getElementById("feeds")
    if (!this.tree || !this.hasFeedsTarget) return

    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.tree, { childList: true, subtree: true, attributes: true })
    // Ages drift between fetches; repaint them once a minute.
    this.timer = setInterval(() => this.refresh(), 60_000)
    this.refresh()
  }

  disconnect() {
    this.observer?.disconnect()
    clearInterval(this.timer)
  }

  refresh() {
    const rows = [...this.tree.querySelectorAll("[data-feed-id]")]
    const unread = rows.reduce((sum, row) => sum + Number(row.dataset.unread || 0), 0)
    const errors = rows.filter((row) => row.dataset.health === "fail").length
    const stale = rows.filter((row) => row.dataset.health === "stale").length
    const fetched = rows.map((row) => Date.parse(row.dataset.fetchedAt)).filter((time) => !isNaN(time))

    this.feedsTarget.textContent = this.format(rows.length)
    this.unreadTarget.textContent = this.format(unread)
    this.errorsTarget.textContent = `${this.format(errors)} ERR`
    // Colour is for meaning: zero errors is idle grey, not fail red.
    this.errorsTarget.classList.toggle("r-code-fail", errors > 0)
    this.errorsTarget.classList.toggle("r-code-idle", errors === 0)
    this.staleTarget.textContent = `${this.format(stale)} STALE`
    this.staleTarget.classList.toggle("r-code-warn", stale > 0)
    this.staleTarget.classList.toggle("r-code-idle", stale === 0)
    this.renderLast(fetched.length ? new Date(Math.max(...fetched)) : null)

    // 01 GROUPS / 01 FEEDS header.
    document.querySelectorAll("[data-tree-summary='feeds']").forEach((el) => { el.textContent = this.format(rows.length) })
    document.querySelectorAll("[data-tree-summary='unread']").forEach((el) => { el.textContent = this.format(unread) })
  }

  // `08:14Z (4 min)`, absolute ISO time on hover.
  renderLast(time) {
    if (!time) {
      this.lastTarget.textContent = "never"
      this.lastTarget.removeAttribute("title")
      return
    }

    const iso = time.toISOString()
    this.lastTarget.title = `${iso.slice(0, 10)} ${iso.slice(11, 16)}Z`
    this.lastTarget.textContent = `${iso.slice(11, 16)}Z (${this.age(time)})`
  }

  // Same buckets as ApplicationHelper#rdr_age.
  age(time) {
    const seconds = Math.max(0, Math.floor((Date.now() - time.getTime()) / 1000))
    if (seconds < 3600) return `${Math.floor(seconds / 60)} min`
    if (seconds < 172800) return `${Math.floor(seconds / 3600)} h`
    return `${this.format(Math.floor(seconds / 86400))} d`
  }

  // Thin space as thousands separator (RDR-01 content rules).
  format(number) {
    return number.toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  }
}
