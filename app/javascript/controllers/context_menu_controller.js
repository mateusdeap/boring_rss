import { Controller } from "@hotwired/stimulus"

// Right-click menu on the feed tree. A feed row (data-feed-id) gets
// Move/Delete feed; a folder row (data-folder-id) gets Rename/Delete
// folder. The menu and the dialogs it opens (folders/_dialogs.html.erb)
// are pointed at the clicked record before they're shown.
export default class extends Controller {
  static targets = ["menu", "feedItems", "folderItems", "deleteFeedLink", "deleteFolderLink"]

  connect() {
    this.hideMenu = this.hideMenu.bind(this);
    document.addEventListener("click", this.hideMenu);
    document.addEventListener("scroll", this.hideMenu);
  }

  disconnect() {
    document.removeEventListener("click", this.hideMenu);
    document.removeEventListener("scroll", this.hideMenu);
  }

  open(event) {
    const row = event.target.closest("[data-feed-id], [data-folder-id]");
    if (!row) return;

    event.preventDefault();
    event.stopPropagation();

    this.row = row;
    const isFeed = "feedId" in row.dataset;
    this.feedItemsTarget.hidden = !isFeed;
    this.folderItemsTarget.hidden = isFeed;
    if (isFeed) {
      this.deleteFeedLinkTarget.href = `/feeds/${row.dataset.feedId}`;
    } else {
      this.deleteFolderLinkTarget.href = `/folders/${row.dataset.folderId}`;
    }

    this.positionMenu(event);
    this.menuTarget.classList.remove("hidden");
  }

  moveFeed() {
    const dialog = document.getElementById("move-feed-dialog");
    const form = dialog.querySelector("form");
    form.action = `/feeds/${this.row.dataset.feedId}`;
    form.elements["feed[folder_name]"].value = this.row.dataset.folderName || "";
    dialog.querySelector("[data-dialog-subject]").textContent = this.row.querySelector(".r-name")?.textContent || "";
    this.showDialog(dialog);
  }

  renameFolder() {
    const dialog = document.getElementById("rename-folder-dialog");
    const form = dialog.querySelector("form");
    form.action = `/folders/${this.row.dataset.folderId}`;
    form.elements["folder[name]"].value = this.row.dataset.folderName || "";
    this.showDialog(dialog);
  }

  showDialog(dialog) {
    this.menuTarget.classList.add("hidden");
    dialog.querySelectorAll("[role='alert']").forEach((el) => { el.textContent = "" });
    dialog.showModal();
    dialog.querySelector("input[type='text']")?.select();
  }

  positionMenu(event) {
    let menuDimensions = this.getDimensions(this.menuTarget);
    this.menuTarget.style.left = `${this.clampValue(
      event.clientX,
      window.innerWidth,
      menuDimensions.width
    )}px`;
    this.menuTarget.style.top = `${this.clampValue(
      event.clientY,
      window.innerHeight,
      menuDimensions.height
    )}px`;
  }

  getDimensions(element) {
    let dimensions = {};
    element.classList.remove("hidden");
    dimensions.width = element.offsetWidth;
    dimensions.height = element.offsetHeight;
    element.classList.add("hidden");
    return dimensions;
  }

  clampValue(value, maxValue, elementDimension) {
    let viewPortDimension = maxValue - elementDimension;
    return value > viewPortDimension ? viewPortDimension : value;
  }

  hideMenu(event) {
    if (this.shouldHideMenu(event)) {
      this.menuTarget.classList.add("hidden");
    }
  }

  shouldHideMenu(event) {
    return (
      !this.menuTarget.contains(event.target) ||
      event.target == this.menuTarget ||
      event.target.closest("a")
    );
  }
}
