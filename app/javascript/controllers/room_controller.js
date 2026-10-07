import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { el, avatar, chainNode, ghostNode, connector, shake } from "degrees/ui"

// A live two-player Six Degrees room. The server owns all state (RoomGame); this controller renders the
// state JSON it receives over ActionCable (and in every POST response), and sends moves back as POSTs.
// `you` is your seat (0/1) or null for a spectator. Stale pushes are dropped by `version`.
export default class extends Controller {
  static targets = ["status", "banner", "invite", "inviteInput", "copyStatus", "players", "pair", "bidPanel", "bidButtons",
                    "callButton", "chainPanel", "chain", "hops", "play", "input", "results", "message", "giveUp",
                    "roundButton", "rules", "rule", "connection", "nameInput", "thinking"]
  static values = { code: String, you: Number, spectator: Boolean, inviteUrl: String, state: Object, peopleUrl: String, baseUrl: String }

  connect() {
    this.state = null
    this.busy = false
    this.items = []
    this.active = -1
    this.seq = 0
    this.everConnected = false
    this.apply(this.stateValue)
    this.subscribe()
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  get me() {
    return this.spectatorValue ? null : this.youValue
  }

  // --- transport ---

  subscribe() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create({ channel: "RoomChannel", code: this.codeValue }, {
      received: (data) => this.apply(data),
      connected: () => {
        this.connectionTarget.hidden = true
        // After a drop we may have missed pushes: ask for the current state rather than trust the stream.
        if (this.everConnected) this.refresh()
        this.everConnected = true
      },
      disconnected: () => { this.connectionTarget.hidden = false }
    })
  }

  async refresh() {
    try {
      const res = await fetch(`${this.baseUrlValue}.json`, { headers: { Accept: "application/json" } })
      if (res.ok) this.apply((await res.json()).state)
    } catch { /* the cable will retry; the next push resyncs us */ }
  }

  async post(action, params = {}) {
    if (this.busy) return null
    this.busy = true
    const body = new URLSearchParams()
    Object.entries(params).forEach(([k, v]) => body.append(k, v))
    try {
      const res = await fetch(`${this.baseUrlValue}/${action}`, {
        method: "POST", body,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
      })
      const data = await res.json().catch(() => ({}))
      if (data.state) this.apply(data.state)
      if (!data.ok && data.message) this.say(data.message)
      return { ...data, status: res.status }
    } catch {
      this.say("Couldn't reach the server. Try again.")
      return null
    } finally {
      this.busy = false
    }
  }

  // --- state -> screen ---

  apply(state) {
    if (this.state && state.version < this.state.version) return
    const prev = this.state
    this.state = state
    if (!prev || prev.round_number !== state.round_number || prev.status !== state.status) this.say("")
    this.render()
  }

  name(seat) {
    return this.state.players[seat]?.name ?? `Player ${seat + 1}`
  }

  label(seat) {
    return seat === this.me ? `${this.name(seat)} (you)` : this.name(seat)
  }

  get opponent() {
    return this.me === null ? null : 1 - this.me
  }

  render() {
    const s = this.state
    this.renderPlayers()
    this.renderBanner()
    this.inviteTarget.hidden = s.players.length >= 2
    this.renderPair()
    this.renderBids()
    this.renderChain()
    this.renderPlay()
    this.renderRound()
    this.renderRules()
  }

  renderPlayers() {
    const s = this.state
    this.playersTarget.replaceChildren()
    for (let seat = 0; seat < 2; seat++) {
      const joined = seat < s.players.length
      const mine = seat === this.me
      const card = el("div", `flex-1 rounded-xl border p-3 ${mine ? "border-slate-900 bg-white" : "border-slate-200 bg-white"} ${s.turn === seat || (s.status === "challenge" && s.challenger === seat) ? "ring-2 ring-amber-400" : ""}`)
      card.append(el("p", "text-xs font-semibold uppercase tracking-wide text-slate-500", joined ? (mine ? "You" : "Opponent") : "Seat open"))
      card.append(el("p", "truncate text-lg font-semibold", joined ? this.name(seat) : "Waiting…"))
      card.append(el("p", "text-sm text-slate-600", `${s.scores[seat]} ${s.scores[seat] === 1 ? "round" : "rounds"} won`))
      this.playersTarget.append(card)
    }
    this.nameInputTarget.parentElement.hidden = this.me === null
    if (this.me !== null && document.activeElement !== this.nameInputTarget) this.nameInputTarget.value = this.name(this.me)
    this.statusTarget.textContent = s.round_number > 0 ? `Round ${s.round_number}` : "Not started"
  }

  renderBanner() {
    const s = this.state
    const me = this.me
    let text, tone = "slate"
    if (s.status === "lobby") {
      text = s.players.length < 2 ? "Waiting for your friend to join. Send them the link above." : "Both players are here. Start the first round when you're ready."
    } else if (s.status === "bidding") {
      const last = s.bids[s.bids.length - 1]
      if (s.turn === me) {
        tone = "amber"
        text = last ? `${this.name(last.seat)} bid ${last.hops}. Your move: bid lower, or call it with "Go for it".` : "Your move: open the bidding. How many hops can you connect them in?"
      } else {
        text = last ? `You bid ${last.hops}. Waiting for ${this.name(s.turn)}…` : `${this.name(s.turn)} opens the bidding…`
        if (me === null) text = last ? `${this.name(last.seat)} bid ${last.hops}. ${this.name(s.turn)} to move.` : `${this.name(s.turn)} opens the bidding.`
      }
    } else if (s.status === "challenge") {
      const who = this.name(s.challenger)
      if (s.challenger === me) {
        tone = "amber"
        text = `Prove it! Connect ${s.start.name} to ${s.target.name} in ${s.max_hops} ${s.max_hops === 1 ? "hop" : "hops"} or fewer. ${s.hops_remaining} left.`
      } else {
        text = `${who} bid ${s.max_hops} and is building the chain. ${s.hops_remaining} ${s.hops_remaining === 1 ? "hop" : "hops"} left.`
      }
    } else {
      const r = s.result
      const winner = this.name(r.winner)
      const hops = `${r.hops} ${r.hops === 1 ? "hop" : "hops"}`
      if (r.kind === "connected") text = `${winner} connected them in ${hops} (bid ${r.bid}) and takes the round!`
      else if (r.kind === "out_of_hops") text = `${this.name(r.challenger)} ran out of hops (bid ${r.bid}). ${winner} takes the round.`
      else text = `${this.name(r.challenger)} gave up. ${winner} takes the round.`
      tone = r.winner === me ? "emerald" : (me === null ? "slate" : "rose")
    }
    const tones = {
      slate: "border-slate-200 bg-slate-50 text-slate-800", amber: "border-amber-300 bg-amber-50 text-amber-900",
      emerald: "border-emerald-300 bg-emerald-50 text-emerald-900", rose: "border-rose-300 bg-rose-50 text-rose-900"
    }
    this.bannerTarget.className = `rounded-xl border p-4 text-center text-lg font-medium ${tones[tone]}`
    this.bannerTarget.textContent = text
    this.thinkingTarget.hidden = !(s.status === "challenge" && s.challenger !== me)
  }

  renderPair() {
    const s = this.state
    this.pairTarget.hidden = !s.start
    if (!s.start) return
    this.pairTarget.replaceChildren()
    const card = (label, person) => {
      const fig = el("figure", "flex w-32 flex-col items-center rounded-xl border border-slate-200 bg-white p-3 text-center shadow-sm sm:w-36 sm:p-4")
      fig.append(el("p", "mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500", label),
                 avatar(person, "h-24 w-24 sm:h-28 sm:w-28"), el("figcaption", "mt-2 text-sm font-semibold sm:text-base", person.name))
      return fig
    }
    this.pairTarget.append(card("Start", s.start), el("span", "mt-20 text-3xl text-slate-400", "→"), card("Target", s.target))
  }

  renderBids() {
    const s = this.state
    const myTurn = s.status === "bidding" && s.turn === this.me
    this.bidPanelTarget.hidden = !myTurn
    if (!myTurn) return
    const lowest = s.bids.length ? s.bids[s.bids.length - 1].hops : 7
    this.bidButtonsTarget.replaceChildren()
    for (let n = 1; n < lowest; n++) {
      const b = el("button", "h-12 w-12 rounded-lg border border-slate-300 bg-white text-lg font-semibold hover:bg-slate-100", String(n))
      b.type = "button"
      b.setAttribute("aria-label", `Bid ${n} ${n === 1 ? "hop" : "hops"}`)
      b.addEventListener("click", () => this.post("bid", { hops: n }))
      this.bidButtonsTarget.append(b)
    }
    this.bidButtonsTarget.parentElement.querySelector("[data-bid-label]").hidden = lowest === 1
    this.bidButtonsTarget.hidden = lowest === 1
    this.callButtonTarget.hidden = s.bids.length === 0
  }

  renderChain() {
    const s = this.state
    this.chainPanelTarget.hidden = s.chain.length === 0 || s.status === "lobby"
    if (this.chainPanelTarget.hidden) return
    this.chainTarget.replaceChildren()
    s.chain.forEach((node, i) => {
      if (i > 0) this.chainTarget.append(connector(node.via))
      this.chainTarget.append(chainNode(node, node.id === s.target.id))
    })
    if (s.status === "challenge") {
      this.chainTarget.append(connector(null), ghostNode(`toward ${s.target.name}`))
    }
    this.hopsTarget.textContent = s.status === "challenge"
      ? `${s.hops_remaining} ${s.hops_remaining === 1 ? "hop" : "hops"} left of ${s.max_hops}`
      : (s.max_hops ? `Bid: ${s.max_hops}` : "")
  }

  renderPlay() {
    const s = this.state
    const building = s.status === "challenge" && s.challenger === this.me
    this.playTarget.hidden = !building
    if (!building) this.hideResults()
    else if (!this.wasBuilding) this.inputTarget.focus()
    this.wasBuilding = building
    const last = s.chain[s.chain.length - 1]
    this.playTarget.querySelector("[data-last-name]").textContent = last ? last.name : ""
  }

  renderRound() {
    const s = this.state
    const playersReady = s.players.length === 2
    const canStart = this.me !== null && playersReady && (s.status === "lobby" || s.status === "round_over")
    this.roundButtonTarget.hidden = !canStart
    this.roundButtonTarget.textContent = this.drawing ? "Drawing a pair…" : (s.status === "lobby" ? "Start game" : "Next round")
    this.roundButtonTarget.disabled = !!this.drawing
  }

  renderRules() {
    const s = this.state
    const editable = this.me === 0 && (s.status === "lobby" || s.status === "round_over")
    this.ruleTargets.forEach((box) => {
      box.checked = !!s.rules[box.dataset.rule]
      box.disabled = !editable
    })
    this.rulesTarget.querySelector("[data-rules-note]").textContent = editable
      ? "You control the rules. They lock once a round is in play."
      : (this.me === null ? "Rules for this room." : (s.status === "bidding" || s.status === "challenge" ? "Locked while a round is in play." : `${this.name(0)} controls the rules.`))
  }

  say(text) {
    this.messageTarget.textContent = text
  }

  // --- actions ---

  async startRound() {
    this.drawing = true
    this.renderRound()
    await this.post("next_round", { round_number: this.state.round_number })
    this.drawing = false
    this.renderRound()
  }

  call() {
    return this.post("challenge")
  }

  giveUp() {
    if (confirm("Give up this round? Your opponent gets the point.")) this.post("give_up")
  }

  rename() {
    const name = this.nameInputTarget.value.trim()
    if (this.me !== null && name !== this.name(this.me)) this.post("set_name", { name })
  }

  changeRule() {
    const params = {}
    this.ruleTargets.forEach((box) => { params[`rules[${box.dataset.rule}]`] = box.checked })
    this.post("set_rules", params)
  }

  async copyInvite() {
    try {
      await navigator.clipboard.writeText(this.inviteUrlValue)
      this.copyStatusTarget.textContent = "Copied!"
    } catch {
      this.inviteInputTarget.select()
      this.copyStatusTarget.textContent = "Press Ctrl/Cmd+C to copy."
    }
  }

  selectInvite() {
    this.inviteInputTarget.select()
  }

  // --- autocomplete + guessing (same flow as the solo game; the server does the checking) ---

  search() {
    clearTimeout(this.timer)
    this.say("")
    const q = this.inputTarget.value.trim()
    if (!q) return this.hideResults()
    this.timer = setTimeout(async () => {
      const seq = ++this.seq
      try {
        const res = await fetch(`${this.peopleUrlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
        if (seq !== this.seq) return
        if (!res.ok) return this.say("Search failed. Try again.")
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
    const inChain = new Set(this.state.chain.map((n) => n.id))
    if (people.length === 0) this.resultsTarget.append(el("li", "p-2 text-slate-500", "No one found."))
    people.forEach((person) => {
      const taken = inChain.has(person.id)
      const btn = el("button", "flex w-full items-center gap-3 rounded-lg p-2 text-left hover:bg-slate-100 disabled:opacity-40 disabled:hover:bg-transparent")
      btn.type = "button"
      btn.disabled = taken
      const text = el("span", "flex min-w-0 flex-col")
      text.append(el("span", "font-medium", person.name))
      const known = taken ? "Already in the chain" : (person.known_for || []).join(", ")
      if (known) text.append(el("span", "truncate text-sm text-slate-500", known))
      btn.append(avatar(person, "h-12 w-12"), text)
      btn.addEventListener("click", () => this.pick(person))
      const li = el("li")
      li.append(btn)
      this.resultsTarget.append(li)
      if (!taken) this.items.push({ person, btn })
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

  async pick(person) {
    if (this.busy) return
    clearTimeout(this.timer)
    this.seq++
    this.hideResults()
    this.inputTarget.value = person.name
    this.inputTarget.disabled = true
    const result = await this.post("guess", { guess_id: person.id })
    this.inputTarget.disabled = false
    if (result && result.ok) {
      this.inputTarget.value = ""
    } else if (result && result.status === 200) {
      shake(this.inputTarget) // a wrong guess costs nothing; keep the text so a typo is easy to fix
      this.inputTarget.select()
    }
    if (!this.playTarget.hidden) this.inputTarget.focus()
  }
}
