// DOM helpers shared by the solo Six Degrees game and the live room: a chain is a wrapping row of
// photo nodes with the shared title on each connector.

export function el(tag, cls = "", text = "") {
  const node = document.createElement(tag)
  if (cls) node.className = cls
  if (text !== "") node.textContent = text
  return node
}

export function avatar(person, size, extra = "") {
  if (person.photo_url) {
    const img = el("img", `${size} shrink-0 rounded-full object-cover ${extra}`)
    img.src = person.photo_url
    img.alt = ""
    return img
  }
  const initials = person.name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("")
  return el("div", `${size} flex shrink-0 items-center justify-center rounded-full bg-slate-200 text-sm font-semibold text-slate-600 ${extra}`, initials)
}

export function chainNode(person, isEnd) {
  const li = el("li", "flex w-24 flex-col items-center text-center")
  li.append(avatar(person, "h-16 w-16", isEnd ? "ring-4 ring-emerald-500" : ""),
            el("span", "mt-1 text-sm font-medium leading-tight", person.name))
  return li
}

export function ghostNode(label) {
  const li = el("li", "flex w-24 flex-col items-center text-center")
  li.append(el("div", "flex h-16 w-16 items-center justify-center rounded-full border-2 border-dashed border-slate-300 text-xl text-slate-400", "?"),
            el("span", "mt-1 text-sm text-slate-500 leading-tight", label))
  return li
}

// The link between two people: "both in Heat (1995)", plus a count if there are more.
export function connector(titles) {
  const li = el("li", "flex h-16 w-28 flex-col items-center justify-center px-1 text-center")
  if (titles && titles.length) {
    const t = titles[0]
    li.append(el("span", "text-xs leading-tight text-slate-600", `both in ${t.title}${t.year ? ` (${t.year})` : ""}`))
    if (titles.length > 1) li.append(el("span", "text-xs text-slate-400", `+${titles.length - 1} more`))
  }
  li.append(el("span", "text-lg leading-none text-slate-400", "→"))
  return li
}

export function shake(input) {
  input.animate(
    [{ transform: "translateX(0)" }, { transform: "translateX(-8px)" }, { transform: "translateX(8px)" },
     { transform: "translateX(-6px)" }, { transform: "translateX(6px)" }, { transform: "translateX(0)" }],
    { duration: 350 })
}
