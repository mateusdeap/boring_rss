import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "deleteLink"]

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
    event.preventDefault();
    event.stopPropagation();

    let clickedElement = event.target;
    let feedId = this.getFeedId(clickedElement);

    if (feedId) {
      this.prepareMenuForFeedItem(feedId);
    }

    this.positionMenu(event);
    this.menuTarget.classList.remove("hidden");
  }

  prepareMenuForFeedItem(feedId) {
    this.updateLinkTargets(feedId);
  }

  updateLinkTargets(feedId) {
    const feedPath = `/feeds/${feedId}`;
    this.deleteLinkTarget.href = feedPath;
  }

  getFeedId(clickedElement) {
    return clickedElement.closest("article").dataset.feedId;
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
