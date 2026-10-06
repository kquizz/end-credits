import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

const MIN_PX = 48
const MAX_PX = 180
const WEB_SCALE = 0.65

// Series picker (search -> chips) plus the overlap bubbles. Plain DOM, no charting library.
export default class extends Controller {
  static targets = ["input", "results", "chips", "button", "status", "canvas", "tooltip", "controls", "gridBtn", "webBtn", "hideGuests", "web"]
  static values = { searchUrl: String, overlapUrl: String }

  connect() {
    this.series = new Map()
    this.seq = 0
    this.view = "grid"
    this.overlap = null
  }

  disconnect() {
    this.simulation?.stop()
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
    this.stopWeb()
    this.controlsTarget.hidden = true
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

  draw(data) {
    this.titles = Object.fromEntries(data.series.map((s) => [s.id, s.title]))
    this.overlap = data
    this.controlsTarget.hidden = data.people.length === 0
    this.redraw()
  }

  showGrid() { this.setView("grid") }
  showWeb() { this.setView("web") }

  setView(view) {
    this.view = view
    this.redraw()
  }

  // Re-renders the current view from the cached data; never refetches.
  redraw() {
    if (!this.overlap) return
    const people = this.visiblePeople()
    this.statusTarget.textContent = people.length
      ? `${people.length} ${people.length === 1 ? "person" : "people"} in at least 2 of these series.`
      : (this.overlap.people.length ? "Nobody left after hiding one-episode guests." : "Nobody appears in more than one of these series.")
    const web = this.view === "web"
    this.canvasTarget.hidden = web
    this.webTarget.hidden = !web
    this.styleToggle(this.gridBtnTarget, !web)
    this.styleToggle(this.webBtnTarget, web)
    this.canvasTarget.replaceChildren()
    this.stopWeb()
    this.tooltipTarget.hidden = true
    if (web) this.drawWeb(people)
    else people.forEach((p) => this.canvasTarget.append(this.bubble(p)))
  }

  styleToggle(btn, on) {
    btn.className = `px-3 py-1.5 ${on ? "bg-slate-900 text-white" : "bg-white text-slate-700"}`
    btn.setAttribute("aria-pressed", String(on))
  }

  // Optionally drops people whose biggest single-show episode count is 1 (one-off guest spots only).
  visiblePeople() {
    if (!this.hideGuestsTarget.checked) return this.overlap.people
    return this.overlap.people.filter((p) => Math.max(...p.shows.map((s) => s.episodes)) > 1)
  }

  stopWeb() {
    this.simulation?.stop()
    this.simulation = null
    this.webTarget.replaceChildren()
  }

  drawWeb(people) {
    const width = Math.max(this.webTarget.clientWidth, 320)
    const height = 680
    const hubR = 46
    const hubs = this.overlap.series.map((s, i, all) => {
      const angle = -Math.PI / 2 + (2 * Math.PI * i) / all.length
      const two = all.length === 2
      const x = two ? width * (i === 0 ? 0.11 : 0.89) : width / 2 + Math.cos(angle) * width * 0.34
      const y = two ? height / 2 : height / 2 + Math.sin(angle) * height * 0.34
      return { id: `s${s.id}`, hub: true, title: s.title, r: hubR, x, y, fx: x, fy: y, seriesId: s.id }
    })
    const hubById = new Map(hubs.map((h) => [h.seriesId, h]))
    const nodes = people.map((p) => {
      const matched = p.shows.map((s) => hubById.get(s.series_id)).filter(Boolean)
      const cx = d3.mean(matched, (h) => h.x) ?? width / 2
      const cy = d3.mean(matched, (h) => h.y) ?? height / 2
      return { id: `p${p.id}`, p, r: (MIN_PX + p.size * (MAX_PX - MIN_PX)) * WEB_SCALE / 2,
               x: cx + (Math.random() - 0.5) * 40, y: cy + (Math.random() - 0.5) * 40 }
    })
    const links = []
    nodes.forEach((n) => n.p.shows.forEach((s) => {
      const hub = hubById.get(s.series_id)
      if (hub) links.push({ source: n.id, target: hub.id })
    }))
    const all = [...hubs, ...nodes]

    const svg = d3.select(this.webTarget).append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`).attr("width", width).attr("height", height)
      .style("display", "block")
    const defs = svg.append("defs")
    nodes.forEach((n) => defs.append("clipPath").attr("id", `clip-${n.id}`)
      .append("circle").attr("r", n.r))

    const link = svg.append("g").attr("stroke", "#cbd5e1").attr("stroke-opacity", 0.8)
      .selectAll("line").data(links).join("line").attr("stroke-width", 1.5)

    const hubSel = svg.append("g").selectAll("g").data(hubs).join("g")
    hubSel.append("circle").attr("r", hubR).attr("fill", "#0f172a")
    hubSel.each((h, i, els) => {
      const text = d3.select(els[i]).append("text").attr("text-anchor", "middle").attr("fill", "#fff")
        .attr("font-size", 12).attr("font-weight", 700).style("pointer-events", "none")
      const lines = this.wrap(h.title, 12, 3)
      lines.forEach((ln, li) => text.append("tspan").attr("x", 0)
        .attr("y", (li - (lines.length - 1) / 2) * 14 + 4).text(ln))
    })

    const personSel = svg.append("g").selectAll("g").data(nodes).join("g").style("cursor", "grab")
    personSel.each((n, i, els) => {
      const g = d3.select(els[i])
      if (n.p.photo_url) {
        g.append("circle").attr("r", n.r).attr("fill", "#e2e8f0")
        g.append("image").attr("href", n.p.photo_url).attr("x", -n.r).attr("y", -n.r)
          .attr("width", n.r * 2).attr("height", n.r * 2).attr("preserveAspectRatio", "xMidYMid slice")
          .attr("clip-path", `url(#clip-${n.id})`)
      } else {
        g.append("circle").attr("r", n.r).attr("fill", "#e2e8f0")
        g.append("text").attr("text-anchor", "middle").attr("dy", "0.35em").attr("fill", "#475569")
          .attr("font-weight", 600).attr("font-size", n.r * 0.8).style("pointer-events", "none")
          .text(this.initials(n.p.name))
      }
      g.append("circle").attr("r", n.r).attr("fill", "none").attr("stroke", "#fff").attr("stroke-width", 2)
      if (n.r >= 34) {
        const label = this.truncate(this.characterLabel(n.p), 26)
        g.append("text").attr("text-anchor", "middle").attr("y", n.r + 12).attr("font-size", 10)
          .attr("font-weight", 600).attr("fill", "#0f172a").style("pointer-events", "none")
          .style("paint-order", "stroke").attr("stroke", "#fff").attr("stroke-width", 3).text(label)
      }
      g.on("mouseenter", (e) => this.showTip(n.p, e))
        .on("mousemove", (e) => this.moveTip(e))
        .on("mouseleave", () => (this.tooltipTarget.hidden = true))
    })

    const sim = d3.forceSimulation(all)
      .force("link", d3.forceLink(links).id((d) => d.id).distance((l) => 70 + l.source.r + hubR).strength(0.08))
      .force("charge", d3.forceManyBody().strength((d) => (d.hub ? 0 : -90)))
      .force("collide", d3.forceCollide((d) => d.r + (d.hub ? 6 : 16)).iterations(3))
      .force("x", d3.forceX(width / 2).strength(0.03))
      .force("y", d3.forceY(height / 2).strength(0.03))
      .on("tick", () => {
        nodes.forEach((n) => {
          n.x = Math.max(n.r, Math.min(width - n.r, n.x))
          n.y = Math.max(n.r, Math.min(height - n.r - 14, n.y))
        })
        link.attr("x1", (l) => l.source.x).attr("y1", (l) => l.source.y)
          .attr("x2", (l) => l.target.x).attr("y2", (l) => l.target.y)
        hubSel.attr("transform", (d) => `translate(${d.x},${d.y})`)
        personSel.attr("transform", (d) => `translate(${d.x},${d.y})`)
      })
    this.simulation = sim

    personSel.call(d3.drag()
      .on("start", (e, d) => { this.tooltipTarget.hidden = true; if (!e.active) sim.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y })
      .on("drag", (e, d) => { d.fx = e.x; d.fy = e.y })
      .on("end", (e, d) => { if (!e.active) sim.alphaTarget(0); d.fx = null; d.fy = null }))
  }

  wrap(text, width, maxLines) {
    const lines = []
    let cur = ""
    text.split(/\s+/).forEach((w) => {
      if (cur && (cur + " " + w).length > width) { lines.push(cur); cur = w } else cur = cur ? `${cur} ${w}` : w
    })
    if (cur) lines.push(cur)
    if (lines.length > maxLines) { lines.length = maxLines; lines[maxLines - 1] = this.truncate(lines[maxLines - 1] + "…", width) }
    return lines
  }

  truncate(text, max) {
    return text.length > max ? `${text.slice(0, max - 1)}…` : text
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
