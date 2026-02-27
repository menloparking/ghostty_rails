import { Controller } from "@hotwired/stimulus"

// Fullscreen CSS applied to the wrapper element.
// Uses fixed positioning to overlay the entire
// viewport, with a high z-index to sit above
// everything else. The flex column layout lets
// the terminal container grow to fill all
// remaining vertical space.
const FULLSCREEN_CLASSES = [
  "fixed",
  "inset-0",
  "z-50",
  "bg-background",
  "p-4",
  "flex",
  "flex-col",
  "overflow-hidden"
]

export default class TerminalFullscreenController
  extends Controller {
  static targets = [
    "wrapper", "btn", "meta", "terminalWrap"
  ]

  declare wrapperTarget: HTMLElement
  declare btnTarget: HTMLElement
  declare hasMetaTarget: boolean
  declare metaTarget: HTMLElement
  declare hasTerminalWrapTarget: boolean
  declare terminalWrapTarget: HTMLElement

  private isFullscreen = false
  private savedClasses: string[] = []
  private savedStyles:
    Record<string, string> = {}
  private savedMetaClasses: string[] = []
  private savedTerminalStyles:
    Record<string, string> = {}
  private savedTerminalClasses: string[] = []
  private savedBodyOverflow = ""

  toggle () {
    if (this.isFullscreen) {
      this.exitFullscreen()
    } else {
      this.enterFullscreen()
    }
  }

  // Allow exiting fullscreen with Escape key
  handleKeydown (event: KeyboardEvent) {
    if (
      event.key === "Escape" &&
      this.isFullscreen
    ) {
      event.preventDefault()
      this.exitFullscreen()
    }
  }

  disconnect () {
    if (this.isFullscreen) {
      this.exitFullscreen()
    }
  }

  // -- Private ------------------------------------

  private enterFullscreen () {
    const el = this.wrapperTarget

    // Save current inline styles so we can
    // restore them
    this.savedStyles = {
      height: el.style.height,
      maxWidth: el.style.maxWidth,
      overflow: el.style.overflow
    }
    this.savedClasses =
      Array.from(el.classList)

    // Lock the page body so it cannot scroll
    // behind the fullscreen overlay
    this.savedBodyOverflow =
      document.body.style.overflow
    document.body.style.overflow = "hidden"

    // Strip layout-constraining classes and
    // apply fullscreen overlay with flex column
    el.className = ""
    el.classList.add(...FULLSCREEN_CLASSES)
    el.style.height = "100vh"
    el.style.maxWidth = ""

    // Collapse metadata bar margin so there is
    // no gap between the bar and the terminal
    if (this.hasMetaTarget) {
      this.savedMetaClasses =
        Array.from(this.metaTarget.classList)
      this.metaTarget.classList.remove("mb-4")
      this.metaTarget.classList.add("mb-2")
    }

    // Let the terminal container stretch to fill
    // all remaining vertical space instead of
    // using a fixed pixel height
    if (this.hasTerminalWrapTarget) {
      const tw = this.terminalWrapTarget
      this.savedTerminalStyles = {
        height: tw.style.height,
        width: tw.style.width
      }
      this.savedTerminalClasses =
        Array.from(tw.classList)
      tw.style.height = ""
      tw.style.width = ""
      tw.classList.add("flex-1", "min-h-0")
    }

    this.setButtonLabel("minimize")
    this.isFullscreen = true

    // Dispatch event so terminal controllers
    // can refit their terminals
    this.dispatch("changed", {
      detail: { fullscreen: true }
    })
  }

  private exitFullscreen () {
    const el = this.wrapperTarget

    // Unlock page body scrolling
    document.body.style.overflow =
      this.savedBodyOverflow

    // Restore original classes and styles
    el.className = ""
    this.savedClasses.forEach(c =>
      el.classList.add(c)
    )
    el.style.height =
      this.savedStyles.height || ""
    el.style.maxWidth =
      this.savedStyles.maxWidth || ""
    el.style.overflow =
      this.savedStyles.overflow || ""

    // Restore metadata bar margin
    if (this.hasMetaTarget) {
      this.metaTarget.className = ""
      this.savedMetaClasses.forEach(c =>
        this.metaTarget.classList.add(c)
      )
    }

    // Restore terminal container dimensions and
    // scrub any inline sizing Ghostty set on its
    // children during the fullscreen session
    if (this.hasTerminalWrapTarget) {
      const tw = this.terminalWrapTarget
      tw.className = ""
      this.savedTerminalClasses.forEach(c =>
        tw.classList.add(c)
      )
      tw.style.height =
        this.savedTerminalStyles.height || ""
      tw.style.width =
        this.savedTerminalStyles.width || ""

      // Ghostty sets explicit pixel dimensions
      // on canvas and wrapper elements inside
      // the terminal container. Clear them so
      // the refit pass can recalculate from the
      // restored layout.
      tw.querySelectorAll<HTMLElement>(
        "canvas, [style]"
      ).forEach(child => {
        child.style.width = ""
        child.style.height = ""
      })
    }

    this.setButtonLabel("maximize")
    this.isFullscreen = false

    // Reset any scroll offset the page
    // accumulated while in fullscreen
    window.scrollTo(0, 0)

    this.dispatch("changed", {
      detail: { fullscreen: false }
    })
  }

  // Update the button's accessible label.
  // The consuming app is responsible for icon
  // rendering (Lucide, SVG, etc). This sets
  // data-action-label so apps can react to
  // the state change.
  private setButtonLabel (name: string) {
    this.btnTarget.setAttribute(
      "data-fullscreen-state", name
    )
    this.btnTarget.setAttribute(
      "aria-label",
      name === "minimize"
        ? "Exit fullscreen"
        : "Enter fullscreen"
    )
  }
}
