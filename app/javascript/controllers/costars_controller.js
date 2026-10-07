import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

const MIN_PX = 48
const MAX_PX = 180
const WEB_SCALE = 0.65

// Series picker (search -> chips) plus the overlap bubbles. Plain DOM, no charting library.
export default class extends Controller {
  static targets = ["input", "results", "chips", "button", "status", "canvas", "tooltip", "detail", "controls", "gridBtn", "webBtn", "allWrap", "allShows", "minWrap", "minValue", "minEp", "web", "watchSection", "watchBtn", "watchStatus", "watchList", "skipSelf", "skipVoice", "skipMarvel"]
  static values = { searchUrl: String, overlapUrl: String, watchNextUrl: String, preload: Array }

  connect() {
    this.series = new Map()
    this.seq = 0
    this.overlap = null
    this.watchSeq = 0
    this.watchLoaded = false
    this.selectedId = null
    this.view = new URLSearchParams(location.search).get("view") === "web" ? "web" : "grid"
    this.pendingMin = parseInt(new URLSearchParams(location.search).get("min"), 10) || 1
    this.pendingAll = new URLSearchParams(location.search).get("all") === "1"
    this.preloadValue.forEach((item) => this.series.set(item.id, item))
    this.drawChips()
    if (this.series.size >= 2) this.render()
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
    this.syncUrl()
  }

  // Keeps the address bar copy-pasteable: /costars?ids[]=1&ids[]=2&view=web
  syncUrl() {
    const parts = [...this.series.keys()].map((id) => `ids[]=${id}`)
    if (this.view === "web") parts.push("view=web")
    if (this.allRequired()) parts.push("all=1")
    if (this.minEpisodes() > 1) parts.push(`min=${this.minEpisodes()}`)
    const query = this.series.size ? `?${parts.join("&")}` : ""
    history.replaceState(null, "", `${location.pathname}${query}`)
  }

  async render() {
    const ids = [...this.series.keys()]
    const params = new URLSearchParams()
    ids.forEach((id) => params.append("ids[]", id))
    this.canvasTarget.replaceChildren()
    this.stopWeb()
    this.clearSelection()
    this.controlsTarget.hidden = true
    this.resetWatch()
    this.watchSectionTarget.hidden = true
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
    this.watchSectionTarget.hidden = data.people.length < 2
    const top = Math.max(1, ...data.people.map((p) => this.peak(p)))
    this.minEpTarget.max = top
    this.minEpTarget.value = Math.min(this.pendingMin ?? this.minEpisodes(), top)
    this.pendingMin = null
    const many = data.series.length >= 3
    this.allWrapTarget.hidden = !many
    this.allShowsTarget.checked = many && (this.pendingAll ?? this.allShowsTarget.checked)
    this.pendingAll = null
    this.minWrapTarget.hidden = top <= 1
    this.syncUrl()
    this.redraw()
  }

  showGrid() { this.setView("grid") }
  showWeb() { this.setView("web") }

  setView(view) {
    this.view = view
    this.syncUrl()
    this.redraw()
  }

  filter() {
    this.syncUrl()
    this.resetWatch()
    this.redraw()
  }

  // Watch-next is fetched on demand: one cached credits lookup per visible person (up to 60).
  async loadWatchNext() {
    const people = this.visiblePeople()
    if (people.length < 2) return
    const params = new URLSearchParams()
    people.forEach((p) => params.append("ids[]", p.id))
    this.overlap.series.forEach((s) => params.append("series[]", s.id))
    params.set("skip_self", this.skipSelfTarget.checked ? "1" : "0")
    params.set("skip_voice", this.skipVoiceTarget.checked ? "1" : "0")
    params.set("skip_marvel", this.skipMarvelTarget.checked ? "1" : "0")
    const seq = ++this.watchSeq
    this.watchBtnTarget.disabled = true
    this.watchListTarget.replaceChildren()
    this.watchStatusTarget.textContent = `Checking what ${Math.min(people.length, 60)} people have been in… the first time can take a few seconds.`
    try {
      const res = await fetch(`${this.watchNextUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (seq !== this.watchSeq) return
      if (!res.ok) throw new Error(data.error || "Something went wrong.")
      this.watchLoaded = true
      this.drawWatchNext(data)
    } catch (e) {
      if (seq !== this.watchSeq) return
      this.watchStatusTarget.textContent = e.message
    } finally {
      if (seq === this.watchSeq) this.watchBtnTarget.disabled = false
    }
  }

  // A toggle changes which credits count, so re-ask the server (cached, so quick) if results are showing.
  watchFilter() {
    if (this.watchLoaded) this.loadWatchNext()
  }

  // The overlap filters changed, so any list on screen is for a different set of people.
  resetWatch() {
    this.watchSeq++
    this.watchLoaded = false
    this.watchListTarget.replaceChildren()
    this.watchStatusTarget.textContent = ""
    this.watchBtnTarget.disabled = false
  }

  drawWatchNext(data) {
    const byId = new Map(this.overlap.people.map((p) => [p.id, p]))
    this.watchListTarget.replaceChildren()
    if (!data.titles.length) {
      this.watchStatusTarget.textContent = "Nothing else is shared by two or more of these people under these filters."
      return
    }
    const skipped = data.people_skipped ? ` (${data.people_skipped} couldn't be checked)` : ""
    this.watchStatusTarget.textContent = `${data.titles.length} titles from ${data.people_checked} people${skipped}.`
    data.titles.forEach((t) => this.watchListTarget.append(this.watchRow(t, t.person_ids.map((id) => byId.get(id)).filter(Boolean))))
  }

  watchRow(t, people) {
    const row = this.el("li", "flex items-center gap-3")
    const info = this.el("div", "min-w-0 flex-1")
    const kind = t.media_type === "tv" ? "TV" : "Movie"
    const link = this.el("a", "font-medium text-blue-700 hover:underline", t.title)
    link.href = `https://www.themoviedb.org/${t.media_type}/${t.id}`
    link.target = "_blank"
    link.rel = "noopener"
    info.append(link,
      this.el("div", "text-sm text-slate-500", [t.year, kind, t.total_episodes > 0 ? `${t.total_episodes} episodes combined` : null].filter(Boolean).join(" · ")),
      this.el("div", "text-sm text-slate-700", `${t.member_count} of these people`))
    const stack = this.el("div", "hidden shrink-0 -space-x-2 sm:flex")
    stack.title = people.map((p) => p.name).join(", ")
    people.slice(0, 6).forEach((p) => {
      const face = p.photo_url ? this.el("img", "h-9 w-9 rounded-full border-2 border-white object-cover") : this.el("div", "flex h-9 w-9 items-center justify-center rounded-full border-2 border-white bg-slate-200 text-xs font-semibold text-slate-600", this.initials(p.name))
      if (p.photo_url) { face.src = p.photo_url; face.alt = ""; face.loading = "lazy" }
      face.title = p.name
      stack.append(face)
    })
    if (people.length > 6) stack.append(this.el("div", "flex h-9 w-9 items-center justify-center rounded-full border-2 border-white bg-slate-100 text-xs font-medium text-slate-600", `+${people.length - 6}`))
    row.append(this.poster(t.poster_url), info, stack)
    row.querySelector("img, div")?.classList.add("shrink-0")
    return row
  }

  // Re-renders the current view from the cached data; never refetches.
  redraw() {
    if (!this.overlap) return
    const people = this.visiblePeople()
    this.minValueTarget.textContent = this.minEpisodes()
    this.statusTarget.textContent = this.statusText(people)
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
    const selected = people.find((p) => p.id === this.selectedId)
    if (selected) this.select(selected)
    else this.clearSelection()
  }

  select(p) {
    this.selectedId = p.id
    this.tooltipTarget.hidden = true
    this.showDetail(p)
    this.highlight()
  }

  clearSelection() {
    this.selectedId = null
    this.detailTarget.hidden = true
    this.highlight()
  }

  showDetail(p) {
    const panel = this.detailTarget
    const close = this.el("button", "absolute right-2 top-2 rounded-full px-2 text-slate-500 hover:bg-slate-100", "×")
    close.type = "button"
    close.setAttribute("aria-label", "Close details")
    close.addEventListener("click", () => this.clearSelection())
    const head = this.el("div", "flex items-center gap-3 pr-6")
    const photo = p.photo_url ? this.el("img", "h-16 w-16 rounded-full object-cover") : this.el("div", "flex h-16 w-16 items-center justify-center rounded-full bg-slate-200 font-semibold text-slate-600", this.initials(p.name))
    if (p.photo_url) { photo.src = p.photo_url; photo.alt = "" }
    head.append(photo, this.el("div", "font-semibold", p.name))
    panel.replaceChildren(close, head, this.el("div", "mt-2 text-sm text-slate-500", `${p.total_episodes} episodes across these series`))
    p.shows.forEach((s) => {
      const row = this.el("div", "mt-2 text-sm")
      row.append(this.el("div", "font-medium", this.titles[s.series_id]),
                 this.el("div", "text-slate-600", `${s.characters.join(" / ") || "Unknown role"} · ${s.episodes} ep`))
      panel.append(row)
    })
    const link = this.el("a", "mt-3 inline-block text-sm text-blue-600 hover:underline", "View on TMDb")
    link.href = `https://www.themoviedb.org/person/${p.id}`
    link.target = "_blank"
    link.rel = "noopener"
    panel.append(link)
    panel.hidden = false
  }

  // Grid: ring the chosen bubble. Web: see paintWeb.
  highlight() {
    const id = this.selectedId
    this.canvasTarget.querySelectorAll("[data-person-id]").forEach((el) => {
      el.firstChild.style.outline = el.dataset.personId === String(id) ? "3px solid #0f172a" : ""
    })
    this.paintWeb()
  }

  // Web: links stay invisible until a person is hovered (transient) or selected (persistent,
  // dims everyone else). Hubs always show.
  paintWeb() {
    const w = this.webParts
    if (!w) return
    const sel = this.selectedId
    const hov = this.hoverId
    const on = sel !== null
    const rank = (l) => (l.source.p.id === sel ? 2 : l.source.p.id === hov ? 1 : 0)
    const hubOn = new Set(w.links.filter((l) => rank(l) === 2).map((l) => l.target.id))
    w.link.attr("stroke", (l) => (rank(l) === 2 ? "#0f172a" : "#475569"))
      .attr("stroke-width", (l) => (rank(l) === 2 ? 3 : 2))
      .attr("stroke-opacity", (l) => [0, 0.7, 0.9][rank(l)])
    w.hubSel.attr("opacity", (h) => (!on || hubOn.has(h.id) ? 1 : 0.25))
    w.personSel.attr("opacity", (n) => (!on || n.p.id === sel || n.p.id === hov ? 1 : 0.25))
    this.drawLabels()
  }

  // Floating "characters + name" label for the selected and hovered people only.
  drawLabels() {
    const w = this.webParts
    const ids = [...new Set([this.selectedId, this.hoverId].filter((id) => id !== null))]
    const nodes = ids.map((id) => w.nodeById.get(id)).filter(Boolean)
    w.labelLayer.selectAll("g").data(nodes, (n) => n.id).join((enter) => {
      const g = enter.append("g")
      const text = g.append("text").attr("text-anchor", "middle").attr("fill", "#0f172a")
        .style("paint-order", "stroke").attr("stroke", "#fff").attr("stroke-width", 4).attr("stroke-linejoin", "round")
      text.append("tspan").attr("class", "who").attr("x", 0).attr("font-size", 12).attr("font-weight", 700)
        .text((n) => this.truncate(this.characterLabel(n.p), 44))
      text.append("tspan").attr("class", "name").attr("x", 0).attr("dy", 14).attr("font-size", 11)
        .attr("fill", "#475569").text((n) => (this.characterLabel(n.p) === n.p.name ? "" : n.p.name))
      return g
    })
    this.placeLabels()
  }

  // Labels sit under the node (above it near the bottom edge), kept inside the frame and at a
  // constant on-screen size regardless of zoom.
  placeLabels() {
    const w = this.webParts
    if (!w) return
    const k = w.k
    w.labelLayer.selectAll("g").each((n, i, els) => {
      const chars = Math.max(n.p.name.length, Math.min(44, this.characterLabel(n.p).length))
      const half = (chars * 3.4 + 4) / k
      const x = Math.max(half, Math.min(w.width - half, n.x))
      const above = n.y + n.r + 40 / k > w.height
      const y = above ? n.y - n.r : n.y + n.r
      const g = d3.select(els[i])
      g.attr("transform", `translate(${x},${y}) scale(${1 / k})`)
      g.select(".who").attr("y", above ? -22 : 14)
    })
  }

  styleToggle(btn, on) {
    btn.className = `px-3 py-1.5 ${on ? "bg-slate-900 text-white" : "bg-white text-slate-700"}`
    btn.setAttribute("aria-pressed", String(on))
  }

  statusText(people) {
    if (!this.overlap.people.length) return "Nobody appears in more than one of these series."
    if (!people.length) return "Nobody left after filtering."
    const min = this.minEpisodes()
    const filters = min > 1 ? `, ${min}+ episodes in a show` : ""
    const scope = this.allRequired() ? `all ${this.overlap.series.length}` : "at least 2"
    return `${people.length} ${people.length === 1 ? "person" : "people"} in ${scope} of these series${filters}.`
  }

  // A person's biggest single-show episode count.
  peak(p) {
    return Math.max(...p.shows.map((s) => s.episodes))
  }

  minEpisodes() {
    return this.hasMinEpTarget ? parseInt(this.minEpTarget.value, 10) || 1 : 1
  }

  allRequired() {
    return this.hasAllShowsTarget && !this.allWrapTarget.hidden && this.allShowsTarget.checked
  }

  // Combines the slider (max episodes in any single matched show must reach it; 1 shows everyone)
  // with the optional "in every selected show" check.
  visiblePeople() {
    const min = this.minEpisodes()
    const everyShow = this.allRequired() ? this.overlap.series.length : 0
    return this.overlap.people.filter((p) => this.peak(p) >= min && p.shows.length >= everyShow)
  }

  stopWeb() {
    this.simulation?.stop()
    this.simulation = null
    this.webParts = null
    this.hoverId = null
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
      .style("display", "block").on("click", () => this.clearSelection())
    const layer = svg.append("g") // zoom/pan transform goes here
    const defs = svg.append("defs")
    nodes.forEach((n) => defs.append("clipPath").attr("id", `clip-${n.id}`)
      .append("circle").attr("r", n.r))

    const link = layer.append("g").attr("stroke", "#475569").style("pointer-events", "none")
      .selectAll("line").data(links).join("line").attr("stroke-opacity", 0)

    const personSel = layer.append("g").selectAll("g").data(nodes).join("g").style("cursor", "grab")
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
      g.on("click", (e) => { e.stopPropagation(); this.select(n.p) })
        .on("mouseenter", (e) => { this.hoverId = n.p.id; this.showTip(n.p, e); this.paintWeb() })
        .on("mousemove", (e) => this.moveTip(e))
        .on("mouseleave", () => { this.hoverId = null; this.tooltipTarget.hidden = true; this.paintWeb() })
    })

    const hubSel = layer.append("g").selectAll("g").data(hubs).join("g")
    hubSel.append("circle").attr("r", hubR).attr("fill", "#0f172a").attr("stroke", "#fff").attr("stroke-width", 3)
    hubSel.each((h, i, els) => {
      const text = d3.select(els[i]).append("text").attr("text-anchor", "middle").attr("fill", "#fff")
        .attr("font-size", 12).attr("font-weight", 700).style("pointer-events", "none")
        .style("paint-order", "stroke").attr("stroke", "#0f172a").attr("stroke-width", 3).attr("stroke-linejoin", "round")
      const lines = this.wrap(h.title, 12, 3)
      lines.forEach((ln, li) => text.append("tspan").attr("x", 0)
        .attr("y", (li - (lines.length - 1) / 2) * 14 + 4).text(ln))
    })

    const labelLayer = layer.append("g").style("pointer-events", "none")
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
        this.placeLabels()
      })
    this.simulation = sim
    this.webParts = { link, hubSel, personSel, links, labelLayer, width, height, k: 1,
                      nodeById: new Map(nodes.map((n) => [n.p.id, n])) }

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
    wrap.dataset.personId = p.id
    wrap.style.cursor = "pointer"
    wrap.addEventListener("mouseenter", (e) => this.showTip(p, e))
    wrap.addEventListener("mousemove", (e) => this.moveTip(e))
    wrap.addEventListener("mouseleave", () => (this.tooltipTarget.hidden = true))
    wrap.addEventListener("focus", () => this.showTip(p, wrap.getBoundingClientRect()))
    wrap.addEventListener("blur", () => (this.tooltipTarget.hidden = true))
    wrap.addEventListener("click", () => this.select(p))
    wrap.addEventListener("keydown", (e) => { if (e.key === "Enter") this.select(p) })
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
