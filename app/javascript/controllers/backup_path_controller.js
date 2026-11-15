import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "result", "button", "dialog", "current", "folders", "browseResult", "chooseButton"]
  static values = { testUrl: String, browseUrl: String }

  disconnect() {
    this.request?.abort()
    this.browseRequest?.abort()
  }

  browse(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
    this.loadFolders(this.inputTarget.value)
  }

  close() {
    this.browseRequest?.abort()
    this.dialogTarget.close()
  }

  choose() {
    this.inputTarget.value = this.selectedPath
    this.clear()
    this.close()
  }

  async loadFolders(path) {
    this.browseRequest?.abort()
    const request = new AbortController()
    this.browseRequest = request
    this.chooseButtonTarget.disabled = true
    this.foldersTarget.replaceChildren()
    this.browseResultTarget.textContent = "Loading folders…"
    try {
      const url = new URL(this.browseUrlValue, window.location.origin)
      if (path) url.searchParams.set("path", path)
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: request.signal })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Unable to list folders.")
      this.selectedPath = data.path
      this.currentTarget.textContent = data.path
      const folders = data.parent ? [{ name: "↑ Up", path: data.parent }, ...data.directories] : data.directories
      for (const folder of folders) {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "block underline break-all"
        button.textContent = folder.name
        button.addEventListener("click", () => this.loadFolders(folder.path))
        this.foldersTarget.append(button)
      }
      this.browseResultTarget.textContent = data.directories.length ? "" : "No subfolders. Additional folders can be created on the server."
      this.chooseButtonTarget.disabled = false
    } catch (error) {
      if (error.name !== "AbortError") this.browseResultTarget.textContent = error.message
    }
  }

  clear() {
    this.request?.abort()
    this.resultTarget.textContent = ""
    this.resultTarget.className = ""
    this.buttonTarget.disabled = false
  }

  async test() {
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    this.buttonTarget.disabled = true
    this.resultTarget.className = ""
    this.resultTarget.textContent = "Checking directory…"
    try {
      const response = await fetch(this.testUrlValue, {
        method: "POST",
        signal: request.signal,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ path: this.inputTarget.value })
      })
      const data = await response.json()
      this.resultTarget.className = response.ok ? "mt-3 rounded-lg bg-green-50 p-3 text-green-800" : "mt-3 rounded-lg bg-red-50 p-3 text-red-800"
      this.resultTarget.textContent = response.ok ? data.message : (data.error || "Unable to check this directory.")
    } catch (error) {
      if (error.name !== "AbortError") this.resultTarget.textContent = "Unable to check this directory. Refresh the page and try again."
    } finally {
      if (this.request === request) this.buttonTarget.disabled = false
    }
  }
}
