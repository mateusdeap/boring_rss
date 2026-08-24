import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleSubmission(event) {
    if (event.detail.success) {
      this.element.close();
    }
  }
}
