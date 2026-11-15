import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image", "title", "closeButton"]

  open(event) {
    const { url, alt } = event.params
    this.imageTarget.src = url
    this.imageTarget.alt = alt
    this.titleTarget.textContent = alt.replace(/^Preview of /, "")
    this.dialogTarget.showModal()
    this.closeButtonTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }
}
