import { Controller } from "@hotwired/stimulus"

// Shows the chosen file before it is uploaded: a thumbnail for images,
// a file-type badge for everything else, plus the name and size.
// It all happens in the browser; nothing is sent until the form is submitted.
export default class extends Controller {
  static targets = ["input", "panel", "image", "badge", "name", "size"]

  disconnect() {
    this.releaseImage()
  }

  show() {
    const file = this.inputTarget.files[0]
    this.releaseImage()

    if (!file) {
      this.panelTarget.hidden = true
      return
    }

    this.nameTarget.textContent = file.name
    this.sizeTarget.textContent = this.humanSize(file.size)

    if (file.type.startsWith("image/")) {
      this.objectUrl = URL.createObjectURL(file)
      this.imageTarget.src = this.objectUrl
      this.imageTarget.alt = `Preview of ${file.name}`
      this.imageTarget.hidden = false
      this.badgeTarget.hidden = true
      // formats the browser can't draw (HEIC on most browsers) fall back to the badge
      this.imageTarget.onerror = () => this.showBadge(file)
    } else {
      this.showBadge(file)
    }

    this.panelTarget.hidden = false
  }

  showBadge(file) {
    const dot = file.name.lastIndexOf(".")
    const extension = dot > 0 ? file.name.slice(dot + 1, dot + 5).toUpperCase() : "FILE"

    this.badgeTarget.textContent = extension
    this.badgeTarget.hidden = false
    this.imageTarget.hidden = true
    this.imageTarget.removeAttribute("src")
  }

  releaseImage() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  }

  humanSize(bytes) {
    const units = ["bytes", "KB", "MB", "GB"]
    let size = bytes
    let unit = 0
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024
      unit++
    }
    return unit === 0 ? `${size} bytes` : `${size.toFixed(1)} ${units[unit]}`
  }
}
