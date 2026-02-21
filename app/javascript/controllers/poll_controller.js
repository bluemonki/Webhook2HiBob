// app/javascript/controllers/poll_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { interval: Number }

    connect() {
        const intervalMs = this.intervalValue || 5000
        this.timer = setInterval(() => {
            if (typeof this.element.reload === "function") this.element.reload()
        }, intervalMs)
    }

    disconnect() {
        if (this.timer) clearInterval(this.timer)
    }
}