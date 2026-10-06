import { Controller } from "@hotwired/stimulus"

const MIN_PX = 48
const MAX_PX = 180

// Series picker (search -> chips) plus the overlap bubbles. Plain DOM, no charting library.
export default class extends Controller {
  static targets = ["input", "results", "chips", "button", "status", "canvas", "tooltip"]
  static values = { searchUrl: String, overlapUrl: String }

  connect() {
    this.series = new Map()
    this.seq = 0
  }

  search() {
    clearTimeout(this.timer)
    const q = this.inputTarget.value.trim()
    if (!q) return this.hideResults()
    this.timer = setTimeout(async () => {
      const seq = ++this.seq
      const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
      if (!res.ok || seq !== this.seq) return
      this.showResults(await res.json())
    }, 300)
  }

  showResults(items) {
    this.resultsTarget.replaceChildren()
    if (items.length === 0) {
      this.resultsTarget.append(this.el("li", "p-2 text-slate-500", "No series found."))
    }
    items.forEach((item) => {
      const li = this.el("li")
      const btn = this.el("button", "flex w-full items-center gap-3 rounded-lg p-2 text-left hover:bg-slate-100")
      btn.type = "button"
      btn.append(this.poster(item.poster_url), this.el("span", "font-medium", item.title),
                 this.el("span", "text-sm text-slate-500", item.year || ""))
      btn.addEventListener("click", () => this.add(item))
      li.append(btn)
      this.resultsTarget.append(li)
    })
    this.resultsTarget.hidden = false
  }

  hideResults() {
    this.resultsTarget.hidden = true
    this.resultsTarget.replaceChildren()
  }

  add(item) {
    this.series.set(item.id, item)
    this.inputTarget.value = ""
    this.hideResults()
    this.drawChips()
  }

  remove(id) {
    this.series.delete(id)
    this.drawChips()
  }

  drawChips() {
    this.chipsTarget.replaceChildren()
    this.series.forEach((item, id) => {
      const chip = this.el("li", "flex items-center gap-2 rounded-full bg-slate-100 py-1 pl-3 pr-1 text-sm font-medium")
      const x = this.el("button", "rounded-full px-2 text-slate-500 hover:bg-slate-200", "×")
      x.type = "button"
      x.setAttribute("aria-label", `Remove ${item.title}`)
      x.addEventListener("click", () => this.remove(id))
      chip.append(this.el("span", "", item.title), x)
      this.chipsTarget.append(chip)
    })
    this.buttonTarget.disabled = this.series.size < 2
  }

  async render() {
    const ids = [...this.series.keys()]
    const params = new URLSearchParams()
    ids.forEach((id) => params.append("ids[]", id))
    this.canvasTarget.replaceChildren()
    this.statusTarget.textContent = "Looking for shared cast…"
    this.buttonTarget.disabled = true
    try {
      const res = await fetch(`${this.overlapUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "Something went wrong.")
      this.draw(data)
    } catch (e) {
      this.statusTarget.textContent = e.message
    } finally {
      this.buttonTarget.disabled = this.series.size < 2
    }
  }

  draw({ series, people }) {
    this.titles = Object.fromEntries(series.map((s) => [s.id, s.title]))
    this.statusTarget.textContent = people.length
      ? `${people.length} ${people.length === 1 ? "person" : "people"} in at least 2 of these series.`
      : "Nobody appears in more than one of these series."
    people.forEach((p) => this.canvasTarget.append(this.bubble(p)))
  }

  bubble(p) {
    const px = Math.round(MIN_PX + p.size * (MAX_PX - MIN_PX))
    const wrap = this.el("div", "flex flex-col items-center text-center")
    wrap.style.width = `${px}px`
    const face = p.photo_url ? this.el("img", "rounded-full object-cover") : this.el("div", "flex items-center justify-center rounded-full bg-slate-200 font-semibold text-slate-600")
    face.style.width = face.style.height = `${px}px`
    if (p.photo_url) { face.src = p.photo_url; face.alt = ""; face.loading = "lazy" }
    else { face.textContent = this.initials(p.name); face.style.fontSize = `${px / 3}px` }
    const label = this.el("span", "mt-1 text-xs font-medium leading-tight", this.characterLabel(p))
    wrap.append(face, label)
    if (label.textContent !== p.name) wrap.append(this.el("span", "text-xs leading-tight text-slate-500", p.name))
    wrap.tabIndex = 0
    wrap.addEventListener("mouseenter", (e) => this.showTip(p, e))
    wrap.addEventListener("mousemove", (e) => this.moveTip(e))
    wrap.addEventListener("mouseleave", () => (this.tooltipTarget.hidden = true))
    wrap.addEventListener("focus", () => this.showTip(p, wrap.getBoundingClientRect()))
    wrap.addEventListener("blur", () => (this.tooltipTarget.hidden = true))
    wrap.addEventListener("click", (e) => this.showTip(p, e))
    return wrap
  }

  showTip(p, pos) {
    const tip = this.tooltipTarget
    tip.replaceChildren(this.el("div", "font-semibold", `${p.name} · ${p.total_episodes} episodes`))
    p.shows.forEach((s) => {
      tip.append(this.el("div", "mt-1 text-slate-300", `${this.titles[s.series_id]}: ${s.episodes} ep`))
    })
    tip.hidden = false
    this.moveTip(pos)
  }

  moveTip(pos) {
    const x = pos.clientX ?? pos.left
    const y = pos.clientY ?? pos.bottom
    this.tooltipTarget.style.left = `${Math.min(x + 12, window.innerWidth - 300)}px`
    this.tooltipTarget.style.top = `${y + 12}px`
  }

  // One character per show the person matched, e.g. "Diane Lockhart / Agnes van Rhijn".
  characterLabel(p) {
    const names = p.shows.map((s) => s.characters[0]).filter(Boolean)
    return names.length ? [...new Set(names)].join(" / ") : p.name
  }

  initials(name) {
    return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("")
  }

  poster(url) {
    if (!url) return this.el("div", "h-14 w-10 rounded bg-slate-200")
    const img = this.el("img", "h-14 w-10 rounded object-cover")
    img.src = url
    img.alt = ""
    return img
  }

  el(tag, cls = "", text = "") {
    const node = document.createElement(tag)
    if (cls) node.className = cls
    if (text !== "") node.textContent = text
    return node
  }
}
