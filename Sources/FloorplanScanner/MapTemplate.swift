// The page itself. Plain HTML, CSS and JS: no build step, no libraries.
let mapTemplate = #"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>swift-floorplan</title>
<style>
  :root { --bg:#f5f5f7; --card:#fff; --line:#d2d2d7; --text:#1d1d1f; --dim:#86868b; --use:#34c759; --usedby:#007aff; --sel:#ff9500; }
  * { box-sizing:border-box; }
  body { margin:0; font:14px -apple-system,"SF Pro Text",sans-serif; background:var(--bg); color:var(--text); display:flex; height:100vh; }
  main { flex:1; overflow:auto; padding:16px; }
  aside { width:340px; border-left:1px solid var(--line); background:var(--card); overflow:auto; padding:16px; }
  h1 { font-size:16px; margin:0 0 4px; } .sub { color:var(--dim); margin-bottom:12px; }
  .bar { display:flex; gap:8px; margin-bottom:16px; } input { flex:1; padding:8px; border:1px solid var(--line); border-radius:8px; } select { padding:8px; border-radius:8px; border:1px solid var(--line); background:var(--card); }
  h2 { font-size:12px; text-transform:uppercase; letter-spacing:.05em; color:var(--dim); margin:20px 0 8px; }
  .room { display:grid; grid-template-columns:repeat(auto-fill,minmax(210px,1fr)); gap:8px; }
  .card { background:var(--card); border:2px solid transparent; border-radius:10px; padding:10px; cursor:pointer; box-shadow:0 1px 2px #0002; }
  .card b { display:block; word-break:break-all; } .card small { color:var(--dim); }
  .card.sel { border-color:var(--sel); } .card.use { border-color:var(--use); } .card.usedby { border-color:var(--usedby); }
  .purpose { margin:-4px 0 8px; } .dim { opacity:.25; } .hide { display:none; }
  aside li { margin:2px 0; } aside a { color:var(--usedby); cursor:pointer; } code { color:var(--dim); }
  /* Reducer tree: roots in one column, children as a grid of tiles. The left edge shows how a child is included. */
  :root { --scope:#34c759; --ifLet:#007aff; --forEach:#af52de; --body:#8e8e93; --enumCase:#ff9500; }
  .legend { display:flex; gap:6px; margin-bottom:12px; }
  .pill { display:inline-block; font-size:11px; font-weight:600; padding:2px 8px; border-radius:99px; color:#fff; white-space:nowrap; }
  .pill.scope { background:var(--scope); } .pill.ifLet { background:var(--ifLet); } .pill.forEach { background:var(--forEach); } .pill.body { background:var(--body); } .pill.enumCase { background:var(--enumCase); }
  .dot { display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:6px; flex:none; }
  .roots { display:flex; flex-direction:column; gap:18px; }
  .rootcard { background:var(--card); border-radius:16px; box-shadow:0 1px 3px #0002; padding:16px 18px; border:2px solid transparent; }
  .rootcard.sel { border-color:var(--sel); }
  .rhead { display:flex; align-items:center; cursor:pointer; } .rhead .name { font-size:16px; font-weight:700; }
  .rcount { margin-left:auto; background:var(--bg); color:var(--dim); border-radius:99px; padding:2px 10px; font-size:12px; }
  .rmeta { color:var(--dim); font-size:12px; margin:4px 0 12px; }
  .coll { display:grid; grid-template-columns:repeat(auto-fill,minmax(270px,1fr)); gap:8px; }
  .tile { background:#fafafc; border:1px solid var(--line); border-left:4px solid var(--body); border-radius:10px; padding:8px 10px; cursor:pointer; min-height:58px; display:flex; flex-direction:column; gap:4px; }
  .tile:hover, .tile.open { box-shadow:0 1px 4px #0002; } .tile.open { background:#fff; }
  .tile.sel { outline:2px solid var(--sel); } .tile.hit { outline:2px solid var(--usedby); }
  .tile .top { display:flex; align-items:center; font-weight:600; line-height:1.2; white-space:nowrap; }
  .tile .file { color:var(--dim); font-size:11px; white-space:nowrap; margin-top:2px; }
  .tile .foot { display:flex; align-items:center; gap:6px; color:var(--dim); font-size:11px; margin-top:auto; }
  .tile .more { margin-left:auto; font-weight:600; font-size:12px; color:var(--text); }
  .tile.scope { border-left-color:var(--scope); } .tile.ifLet { border-left-color:var(--ifLet); } .tile.forEach { border-left-color:var(--forEach); } .tile.body { border-left-color:var(--body); } .tile.enumCase { border-left-color:var(--enumCase); }
  .subcoll { grid-column:1/-1; background:var(--bg); border-radius:12px; padding:10px; border-left:4px solid var(--line); }
  .subcoll.scope { border-left-color:var(--scope); } .subcoll.ifLet { border-left-color:var(--ifLet); } .subcoll.forEach { border-left-color:var(--forEach); } .subcoll.body { border-left-color:var(--body); } .subcoll.enumCase { border-left-color:var(--enumCase); }
  .subcoll > .label { color:var(--dim); font-size:12px; margin-bottom:8px; } .subcoll .tile { background:#fff; }
  .rpanel ul { list-style:none; margin:0; padding:0; } .rpanel li { display:flex; gap:6px; align-items:center; }
</style></head>
<body>
<main><h1>swift-floorplan</h1><div class="sub" id="sub"></div>
  <div class="bar"><input id="q" placeholder="Filter by file, folder, feature or type name"><select id="mode"><option value="folder">Group by folder</option><option value="feature">Group by feature</option><option value="tree">Reducer tree</option></select></div><div id="rooms"></div></main>
<aside id="side"><div class="sub">Click a file card. Green = files it uses. Blue = files that use it.</div></aside>
<script>
const DATA = __SCAN_DATA__;
const NAMES = __ROOM_NAMES__;
const FEATURE_OF = __FEATURE_OF__;
const FEATURES = __FEATURES__;
const files = DATA.files;
// Map each type's last name part to the files that define it. Names defined in several files
// (State, Action...) are ambiguous, so they make no link.
const definers = new Map();
for (const f of files) for (const t of f.types) {
  const n = t.name.split(".").pop();
  if (!definers.has(n)) definers.set(n, new Set());
  definers.get(n).add(f.path);
}
const uses = new Map(files.map(f => [f.path, new Set()]));
const usedBy = new Map(files.map(f => [f.path, new Set()]));
for (const f of files) for (const t of f.types) for (const r of [...t.references, ...t.inherits]) {
  const d = definers.get(r);
  if (d && d.size === 1) { const [to] = d; if (to !== f.path) { uses.get(f.path).add(to); usedBy.get(to).add(f.path); } }
}
const roomOf = p => p.includes("/") ? p.slice(0, p.lastIndexOf("/")) : "(top level)";
const featureInfo = new Map(FEATURES.map(x => [x.name, x]));
const UNASSIGNED = "Unassigned";
const hasFeatures = FEATURES.length > 0;
document.getElementById("sub").textContent = `${files.length} files, ${files.reduce((n, f) => n + f.types.length, 0)} types in ${DATA.root}`;
const roomsEl = document.getElementById("rooms"), modeEl = document.getElementById("mode");
let cards = new Map();
const reducers = files.flatMap(f => f.types.filter(t => t.isReducer).map(t => ({ ...t, path: f.path })));
if (!hasFeatures) modeEl.querySelector("[value=feature]").remove();
if (!reducers.length) modeEl.querySelector("[value=tree]").remove();
modeEl.hidden = modeEl.options.length < 2;
modeEl.onchange = () => draw(modeEl.value);
// Group the files into titled sections: by folder, or by feature when a features file was given.
function draw(mode) {
  if (mode === "tree") return drawTree();
  const groups = new Map();
  for (const f of files) {
    const key = mode === "feature" ? (FEATURE_OF[f.path] ?? UNASSIGNED) : roomOf(f.path);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(f);
  }
  roomsEl.replaceChildren(); cards = new Map();
  const keys = [...groups.keys()].sort((a, b) => (a === UNASSIGNED) - (b === UNASSIGNED) || (mode === "feature" ? FEATURES.findIndex(x => x.name === a) - FEATURES.findIndex(x => x.name === b) : 0));
  for (const key of keys) {
    const label = mode === "feature" ? featureInfo.get(key) : NAMES[key];
    const h = document.createElement("h2");
    h.textContent = label ? (mode === "feature" ? `${label.name} (${groups.get(key).length} files)` : `${label.name} (${key})`) : key;
    roomsEl.append(h);
    if (label) { const p = document.createElement("div"); p.className = "purpose"; p.textContent = label.purpose; roomsEl.append(p); }
    const grid = document.createElement("div"); grid.className = "room";
    for (const f of groups.get(key)) {
      const c = document.createElement("div"); c.className = "card";
      c.innerHTML = `<b></b><small></small>`;
      c.firstChild.textContent = mode === "feature" ? f.path : f.path.split("/").pop();
      c.lastChild.textContent = f.types.map(t => t.name).join(", ") || "no types";
      c.onclick = () => select(f.path); cards.set(f.path, c); grid.append(c);
    }
    roomsEl.append(grid);
  }
  document.getElementById("q").oninput();
}
// Reducer tree. Reducers nobody includes are the roots, one card per row. Their children are tiles
// in a grid; a tile with a number opens its own children right below it.
const byName = new Map(reducers.map(r => [r.name, r]));
const kidsOf = r => r.composes.filter(c => byName.has(c.child));
const parentsOf = new Map(), creators = new Map();
for (const r of reducers) for (const c of kidsOf(r)) {
  if (!parentsOf.has(c.child)) parentsOf.set(c.child, []);
  parentsOf.get(c.child).push({ name: r.name, via: c.via });
}
for (const f of files) for (const t of f.types) for (const r of t.createsStores) {
  if (!creators.has(r)) creators.set(r, []);
  creators.get(r).push(t.name);
}
const PALETTE = ["#007aff", "#34c759", "#ff9500", "#af52de", "#ff2d55", "#5ac8fa", "#ffcc00", "#5856d6", "#00c7be", "#a2845e", "#ff6b6b", "#4cd964"];
const featureOf = r => FEATURE_OF[r.path] ?? UNASSIGNED;
const dot = r => { const i = FEATURES.findIndex(x => x.name === featureOf(r)); return `<span class="dot" style="background:${i < 0 ? "#c7c7cc" : PALETTE[i % PALETTE.length]}" title="${esc(featureOf(r))}"></span>`; };
const mk = (tag, cls, html) => { const e = document.createElement(tag); e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };
const reducerText = r => (r.name + " " + r.path + " " + featureOf(r)).toLowerCase();
function countAll(r, seen = new Set()) {
  if (seen.has(r.name)) return 0;
  seen.add(r.name);
  return kidsOf(r).reduce((n, c) => n + 1 + countAll(byName.get(c.child), seen), 0);
}
function tile(r, via, seen) {
  const kids = kidsOf(r).filter(c => !seen.has(c.child));
  const t = mk("div", "tile " + (via ?? ""), `<div class="top">${dot(r)}${esc(r.name)}</div><div class="foot">${via ? `<span class="pill ${via}">${via}</span>` : ""}${kids.length ? `<span class="more">${kids.length} ›</span>` : ""}</div><div class="file">${esc(r.path.split("/").pop())}</div>`);
  t.dataset.name = r.name;
  t.onclick = e => {
    e.stopPropagation(); selectReducer(r, t);
    if (!kids.length) return;
    const next = t.nextElementSibling;
    if (next?.classList.contains("subcoll") && next.dataset.for === r.name) { next.remove(); t.classList.remove("open"); return; }
    t.classList.add("open");
    const sub = mk("div", "subcoll " + (via ?? ""), `<div class="label">${esc(r.name)} includes ${kids.length}</div>`);
    sub.dataset.for = r.name;
    const grid = mk("div", "coll"), nextSeen = new Set([...seen, r.name]);
    for (const c of kids) grid.append(tile(byName.get(c.child), c.via, nextSeen));
    sub.append(grid); t.after(sub);
  };
  return t;
}
function selectReducer(r, node) {
  document.querySelectorAll(".sel").forEach(e => e.classList.remove("sel")); node.classList.add("sel");
  const link = n => `<a data-n="${esc(n)}">${esc(n)}</a>`;
  const rows = (list, text) => list.map(p => `<li>${link(p.name ?? p.child)} <span class="pill ${p.via}">${p.via}</span></li>`).join("") || `<li><code>${text}</code></li>`;
  const made = creators.get(r.name) ?? [];
  document.getElementById("side").innerHTML = `<div class="rpanel"><h1>${dot(r)}${esc(r.name)}</h1><div class="sub">${esc(r.path)}<br>Feature: ${esc(featureOf(r))}</div>
    <h2>Included by</h2><ul>${rows(parentsOf.get(r.name) ?? [], "nobody (root)")}</ul>
    <h2>Includes</h2><ul>${rows(kidsOf(r), "nothing")}</ul>
    <h2>Store created by</h2><ul>${made.map(n => `<li>${esc(n)}</li>`).join("") || "<li><code>no view</code></li>"}</ul></div>`;
  document.querySelectorAll("#side a").forEach(a => a.onclick = () => {
    const n = byName.get(a.dataset.n);
    selectReducer(n, document.querySelector(`.tile[data-name="${CSS.escape(n.name)}"]`) ?? mk("div", ""));
  });
}
function drawTree() {
  const included = new Set(parentsOf.keys());
  const roots = reducers.filter(r => !included.has(r.name) && (r.composes.length || creators.has(r.name))).sort((a, b) => countAll(b) - countAll(a));
  roomsEl.replaceChildren(); cards = new Map();
  roomsEl.append(mk("div", "sub", `${reducers.length} reducers, ${roots.length} roots. Click a tile with a number to open its children.`));
  roomsEl.append(mk("div", "legend", ["scope", "ifLet", "forEach", "body", "enumCase"].map(v => `<span class="pill ${v}">${v}</span>`).join("")));
  const list = mk("div", "roots");
  for (const r of roots) {
    const card = mk("div", "rootcard", `<div class="rhead">${dot(r)}<span class="name">${esc(r.name)}</span><span class="rcount">${countAll(r)} reducers</span></div><div class="rmeta">${esc(r.path)}${creators.has(r.name) ? ` · created by ${esc(creators.get(r.name).join(", "))}` : ""}</div>`);
    card.querySelector(".rhead").onclick = () => selectReducer(r, card);
    const grid = mk("div", "coll");
    for (const k of kidsOf(r)) grid.append(tile(byName.get(k.child), k.via, new Set([r.name])));
    card.append(grid); card.dataset.name = r.name; list.append(card);
  }
  roomsEl.append(list);
  document.getElementById("q").oninput();
}
// A root stays visible when it or anything below it matches the filter. Matching tiles get an outline.
function filterTree(q) {
  const hit = (r, seen = new Set()) => !seen.has(r.name) && (seen.add(r.name), !q || reducerText(r).includes(q) || kidsOf(r).some(c => hit(byName.get(c.child), seen)));
  for (const card of document.querySelectorAll(".rootcard")) card.classList.toggle("hide", !hit(byName.get(card.dataset.name)));
  for (const t of document.querySelectorAll(".tile")) t.classList.toggle("hit", !!q && reducerText(byName.get(t.dataset.name)).includes(q));
}
function select(path) {
  for (const [p, c] of cards) {
    c.className = "card" + (p === path ? " sel" : uses.get(path).has(p) ? " use" : usedBy.get(path).has(p) ? " usedby" : " dim");
  }
  const f = files.find(x => x.path === path), side = document.getElementById("side");
  const list = set => [...set].sort().map(p => `<li><a data-p="${esc(p)}">${esc(p)}</a></li>`).join("") || "<li><code>none</code></li>";
  side.innerHTML = `<h1>${esc(f.path)}</h1><div class="sub">imports: ${esc(f.imports.join(", ") || "none")}</div>
    <h2>Types</h2><ul>${f.types.map(t => `<li>${t.kind} <b>${esc(t.name)}</b> <code>line ${t.line}${t.inherits.length ? " : " + esc(t.inherits.join(", ")) : ""}</code></li>`).join("") || "<li><code>none</code></li>"}</ul>
    <h2>Uses</h2><ul>${list(uses.get(path))}</ul><h2>Used by</h2><ul>${list(usedBy.get(path))}</ul>`;
  side.querySelectorAll("a").forEach(a => a.onclick = () => select(a.dataset.p));
}
function esc(s) { return s.replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]); }
document.getElementById("q").oninput = () => {
  const q = document.getElementById("q").value.toLowerCase();
  if (modeEl.value === "tree") return filterTree(q);
  for (const f of files) cards.get(f.path)?.classList.toggle("hide", q && !(f.path + " " + (NAMES[roomOf(f.path)]?.name ?? "") + " " + (FEATURE_OF[f.path] ?? "") + " " + f.types.map(t => t.name).join(" ")).toLowerCase().includes(q));
};
draw("folder");
</script></body></html>
"""#
