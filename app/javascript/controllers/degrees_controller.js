import { Controller } from "@hotwired/stimulus"

// Six Degrees: autocomplete a name, ask the server whether they share a credit with the end of the
// chain, and grow the chain until the target joins it. Plain DOM; the chain is a wrapping row of photo
// nodes with the shared title on each connector.
export default class extends Controller {
  static targets = ["input", "results", "message", "chain", "win", "score", "shareStatus", "play", "lastName",
                    "skipSelf", "skipVoice", "skipMarvel", "moviesOnly", "yearFrom", "yearTo"]
  static values = { start: Object, target: Object, tier: String, peopleUrl: String, guessUrl: String, gamePath: String }

  connect() {
    this.chain = [{ ...this.startValue, via: null }]
    this.seq = 0
    this.items = []
    this.active = -1
    this.busy = false
    this.won = false
    this.drawChain()
  }

  // --- autocomplete ---

  search() {
    clearTimeout(this.timer)
    this.messageTarget.textContent = ""
    const q = this.inputTarget.value.trim()
    if (!q) return this.hideResults()
    this.timer = setTimeout(async () => {
      const seq = ++this.seq
      try {
        const res = await fetch(`${this.peopleUrlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
        if (seq !== this.seq) return
        if (!res.ok) return this.say((await this.errorOf(res)) || "Search failed. Try again.")
        this.showResults(await res.json())
      } catch {
        if (seq === this.seq) this.say("Couldn't reach the server.")
      }
    }, 250)
  }

  showResults(people) {
    this.resultsTarget.replaceChildren()
    this.items = []
    this.active = -1
    if (people.length === 0) this.resultsTarget.append(this.el("li", "p-2 text-slate-500", "No one found."))
    people.forEach((person) => {
      const inChain = this.chain.some((n) => n.id === person.id)
      const btn = this.el("button", "flex w-full items-center gap-3 rounded-lg p-2 text-left hover:bg-slate-100 disabled:opacity-40 disabled:hover:bg-transparent")
      btn.type = "button"
      btn.disabled = inChain
      const text = this.el("span", "flex min-w-0 flex-col")
      text.append(this.el("span", "font-medium", person.name))
      const known = inChain ? "Already in your chain" : (person.known_for || []).join(", ")
      if (known) text.append(this.el("span", "truncate text-sm text-slate-500", known))
      btn.append(this.avatar(person, "h-12 w-12"), text)
      btn.addEventListener("click", () => this.pick(person))
      const li = this.el("li")
      li.append(btn)
      this.resultsTarget.append(li)
      if (!inChain) this.items.push({ person, btn })
    })
    this.resultsTarget.hidden = false
  }

  hideResults() {
    this.resultsTarget.hidden = true
    this.resultsTarget.replaceChildren()
    this.items = []
    this.active = -1
  }

  key(event) {
    if (event.key === "Escape") return this.hideResults()
    if (this.resultsTarget.hidden || this.items.length === 0) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.active = (this.active + step + this.items.length) % this.items.length
      this.items.forEach((item, i) => item.btn.classList.toggle("bg-slate-100", i === this.active))
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.pick(this.items[Math.max(this.active, 0)].person)
    }
  }

  // --- guessing ---

  async pick(person) {
    if (this.busy || this.won) return
    this.busy = true
    clearTimeout(this.timer)
    this.seq++
    this.hideResults()
    this.say("")
    this.inputTarget.value = person.name
    this.inputTarget.disabled = true
    try {
      const res = await fetch(`${this.guessUrlValue}?${this.guessParams(person)}`, { headers: { Accept: "application/json" } })
      const body = await res.json().catch(() => ({}))
      if (res.ok && body.ok) return this.accept(body)
      this.reject(body.message || "Something went wrong. Try again.", res.ok)
    } catch {
      this.reject("Couldn't reach the server. Try again.", false)
    } finally {
      this.busy = false
      this.inputTarget.disabled = false
      if (!this.won) this.inputTarget.focus()
    }
  }

  guessParams(person) {
    const params = new URLSearchParams({ chain_last_id: this.last.id, guess_id: person.id })
    this.chain.forEach((n) => params.append("chain[]", n.id))
    params.set("skip_self", this.skipSelfTarget.checked)
    params.set("skip_voice", this.skipVoiceTarget.checked)
    params.set("skip_marvel", this.skipMarvelTarget.checked)
    params.set("movies_only", this.moviesOnlyTarget.checked)
    if (this.yearFromTarget.value) params.set("year_from", this.yearFromTarget.value)
    if (this.yearToTarget.value) params.set("year_to", this.yearToTarget.value)
    return params
  }

  accept(body) {
    this.chain.push({ ...body.person, via: body.titles })
    this.inputTarget.value = ""
    const reached = body.person.id === this.targetValue.id
    if (reached) this.won = true
    this.drawChain()
    if (reached) this.win()
  }

  // A wrong guess costs nothing: shake, explain, keep the text so a typo is easy to fix.
  reject(message, shake) {
    this.say(message)
    if (shake) {
      this.inputTarget.animate(
        [{ transform: "translateX(0)" }, { transform: "translateX(-8px)" }, { transform: "translateX(8px)" },
         { transform: "translateX(-6px)" }, { transform: "translateX(6px)" }, { transform: "translateX(0)" }],
        { duration: 350 })
    }
    this.inputTarget.select()
  }

  say(text) {
    this.messageTarget.textContent = text
  }

  async errorOf(res) {
    return (await res.json().catch(() => ({}))).message
  }

  // --- finish ---

  win() {
    this.won = true
    const hops = this.chain.length - 1
    this.scoreTarget.textContent = `${hops} ${hops === 1 ? "hop" : "hops"}. Lower is better.`
    this.winTarget.hidden = false
    this.playTarget.hidden = true
    this.winTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  async share() {
    const hops = this.chain.length - 1
    const params = new URLSearchParams({ start: this.startValue.id, target: this.targetValue.id })
    if (this.tierValue) params.set("tier", this.tierValue)
    const url = `${location.origin}${this.gamePathValue}?${params}`
    const text = `Six Degrees: ${this.startValue.name} → ${this.targetValue.name} in ${hops} ${hops === 1 ? "hop" : "hops"} ${url}`
    try {
      await navigator.clipboard.writeText(text)
      this.shareStatusTarget.textContent = "Copied!"
    } catch {
      this.shareStatusTarget.textContent = text
    }
  }

  // --- drawing ---

  get last() {
    return this.chain[this.chain.length - 1]
  }

  drawChain() {
    this.chainTarget.replaceChildren()
    this.chain.forEach((node, i) => {
      if (i > 0) this.chainTarget.append(this.connector(node.via))
      this.chainTarget.append(this.node(node))
    })
    if (!this.won) {
      this.chainTarget.append(this.connector(null))
      this.chainTarget.append(this.ghost())
    }
    this.lastNameTarget.textContent = this.last.name
  }

  node(person) {
    const li = this.el("li", "flex w-24 flex-col items-center text-center")
    const isEnd = person.id === this.targetValue.id
    li.append(this.avatar(person, "h-16 w-16", isEnd ? "ring-4 ring-emerald-500" : ""),
              this.el("span", "mt-1 text-sm font-medium leading-tight", person.name))
    return li
  }

  ghost() {
    const li = this.el("li", "flex w-24 flex-col items-center text-center")
    li.append(this.el("div", "flex h-16 w-16 items-center justify-center rounded-full border-2 border-dashed border-slate-300 text-xl text-slate-400", "?"),
              this.el("span", "mt-1 text-sm text-slate-500 leading-tight", `toward ${this.targetValue.name}`))
    return li
  }

  // The link between two people: "both in Heat (1995)", plus a count if there are more.
  connector(titles) {
    const li = this.el("li", "flex h-16 w-28 flex-col items-center justify-center px-1 text-center")
    if (titles && titles.length) {
      const t = titles[0]
      li.append(this.el("span", "text-xs leading-tight text-slate-600", `both in ${t.title}${t.year ? ` (${t.year})` : ""}`))
      if (titles.length > 1) li.append(this.el("span", "text-xs text-slate-400", `+${titles.length - 1} more`))
    }
    li.append(this.el("span", "text-lg leading-none text-slate-400", "→"))
    return li
  }

  avatar(person, size, extra = "") {
    if (person.photo_url) {
      const img = this.el("img", `${size} shrink-0 rounded-full object-cover ${extra}`)
      img.src = person.photo_url
      img.alt = ""
      return img
    }
    const initials = person.name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("")
    return this.el("div", `${size} flex shrink-0 items-center justify-center rounded-full bg-slate-200 text-sm font-semibold text-slate-600 ${extra}`, initials)
  }

  el(tag, cls = "", text = "") {
    const node = document.createElement(tag)
    if (cls) node.className = cls
    if (text !== "") node.textContent = text
    return node
  }
}
