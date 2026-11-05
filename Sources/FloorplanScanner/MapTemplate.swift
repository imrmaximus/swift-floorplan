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
  <div class="bar"><input id="q" placeholder="Filter by file, folder, feature or type name"><select id="mode"><option value="folder">Group by folder</option><option value="feature">Group by feature</option><option value="tree">Reducer tree</option><option value="deps">Dependencies</option><option value="entities">Core Data</option></select></div><div id="rooms"></div></main>
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
  if (mode === "deps") return drawDeps();
  if (mode === "entities") return drawEntities();
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
// Dependencies view. A dependency is a key read with @Dependency(\.key). Keys declared in the scan show their
// type and the frameworks their file imports (EventKit, CoreData...), so "what touches the database" is one filter away.
const BORING = new Set(["ComposableArchitecture", "Dependencies", "Foundation", "SwiftUI", "DesignSystem", "AppKit", "UIKit"]);
// ponytail: a type name starting with EK/CK/UN plus a capital (EKEventStore) shows its framework even when the file
// forgot the import. Three prefixes only; add more when a real app needs them.
const PREFIX_FRAMEWORK = { EK: "EventKit", CK: "CloudKit", UN: "UserNotifications" };
const depUsers = new Map(), depDecl = new Map();
for (const f of files) {
  for (const d of f.dependencyKeys ?? []) depDecl.set(d.name, { type: d.type, path: f.path });
  for (const t of f.types) for (const k of t.dependencies ?? []) {
    if (!depUsers.has(k)) depUsers.set(k, []);
    depUsers.get(k).push({ name: t.name, path: f.path });
  }
}
if (!depUsers.size) modeEl.querySelector("[value=deps]").remove();
// Core Data is shown only when the code uses its types, because most files import it out of habit. A type counts when
// it mentions NSManagedObject and friends, or a record class (a subclass of NSManagedObject). One hop is followed, so a
// client that goes through a repository still counts; two hops would reach nearly everything.
const COREDATA = /^(NSManagedObject|NSFetchRequest|NSPersistent|NSFetchedResults|NSBatch|NSEntityDescription)/;
const isTest = (path, name) => /Tests?\//.test(path) || /Tests?$/.test(name);
const typeIndex = new Map(), recordNames = new Set(); // name -> { declared: how many real declarations, parts: struct + extensions }
for (const f of files) for (const t of f.types) {
  const isExt = t.kind === "extension", n = t.name.split(".").pop().replace(" (extension)", "");
  if (!isTest(f.path, t.name)) {
    if (!typeIndex.has(n)) typeIndex.set(n, { declared: 0, parts: [] });
    const entry = typeIndex.get(n); entry.parts.push(t); if (!isExt) entry.declared++;
  }
  if (t.inherits.some(i => COREDATA.test(i))) recordNames.add(n);
}
if (!recordNames.size) modeEl.querySelector("[value=entities]").remove();
// A bare call to a function declared once at the top level of a file counts like a reference to a type: that file's loose code is read.
const functionFiles = new Map();
for (const f of files) if (!isTest(f.path, "")) for (const n of f.functions ?? []) functionFiles.set(n, functionFiles.has(n) ? null : f);
const usesCoreData = t => t.references.some(r => COREDATA.test(r) || recordNames.has(r));
// A name declared twice (State, Action...) is ambiguous and is skipped; a struct plus its extensions is one type.
const reachesCoreData = t => usesCoreData(t)
  || t.references.some(r => { const e = typeIndex.get(r); return e?.declared === 1 && e.parts.some(usesCoreData); })
  || (t.calls ?? []).some(c => functionFiles.get(c)?.types.some(x => x.kind === "topLevel" && usesCoreData(x)));
// The files that make up a dependency: where its key is declared, where its type is defined, and where types named
// after it live (LiveReminderClient for ReminderClient). Test types are left out.
function relatedOf(d) {
  const named = files.flatMap(f => f.types.filter(t => t.name.split(".")[0].includes(d.type) && !isTest(f.path, t.name)).map(t => ({ path: f.path, t })));
  const paths = new Set([d.path, ...(definers.get(d.type) ?? []), ...named.map(n => n.path)]);
  return { named, sameFiles: files.filter(f => paths.has(f.path)) };
}
// A dependency touches Core Data when its code does, or when it reads another dependency that does.
const coreDataMemo = new Map();
function touchesCoreData(key) {
  if (coreDataMemo.has(key)) return coreDataMemo.get(key);
  coreDataMemo.set(key, false); // stops loops between dependencies
  const d = depDecl.get(key);
  const yes = !!d && relatedOf(d).sameFiles.some(f => f.types.some(t => reachesCoreData(t) || (t.dependencies ?? []).some(touchesCoreData)));
  coreDataMemo.set(key, yes);
  return yes;
}
// Frameworks of a dependency: imports of its files, plus framework names seen in the types named after it.
function frameworksOf(key, d) {
  const { named, sameFiles } = relatedOf(d);
  const kits = new Set(sameFiles.flatMap(f => f.imports).filter(m => !BORING.has(m) && m !== "CoreData"));
  for (const { t } of named) for (const r of t.references) if (PREFIX_FRAMEWORK[r.slice(0, 2)] && /[A-Z]/.test(r[2] ?? "")) kits.add(PREFIX_FRAMEWORK[r.slice(0, 2)]);
  if (touchesCoreData(key)) kits.add("CoreData");
  return [...kits].sort();
}
// Core Data view. One card per record class (a subclass of NSManagedObject). It lists the types that mention the record,
// and the dependencies whose own client type does (types named after it, plus one hop through uniquely declared types).
const recordUsers = new Map([...recordNames].map(n => [n, []])), recordDeps = new Map([...recordNames].map(n => [n, new Set()]));
for (const f of files) for (const t of f.types) {
  if (isTest(f.path, t.name)) continue;
  const own = t.name.split(".")[0].replace(" (extension)", "");
  for (const r of t.references) if (recordNames.has(r) && r !== own) recordUsers.get(r).push({ name: t.name, path: f.path });
}
for (const [key, d] of depDecl) for (const { t } of relatedOf(d).named) for (const r of t.references) {
  recordDeps.get(r)?.add(key);
  const e = typeIndex.get(r);
  if (e?.declared === 1) for (const p of e.parts) for (const r2 of p.references) recordDeps.get(r2)?.add(key);
}
function entityCard(name) {
  const users = recordUsers.get(name), deps = [...recordDeps.get(name)].sort();
  const card = mk("div", "tile depcard", `<div class="top">${esc(name)}</div><div class="foot"><span>${deps.length} dependencies</span><span class="more">${users.length} ›</span></div><div class="file">${esc(deps.slice(0, 3).join(" · "))}${deps.length > 3 ? " …" : ""}</div>`);
  card.dataset.text = [name, ...deps, ...users.map(u => u.name)].join(" ").toLowerCase();
  card.onclick = () => {
    const next = card.nextElementSibling;
    if (next?.classList.contains("subcoll")) { next.remove(); card.classList.remove("open"); return; }
    card.classList.add("open");
    const sub = mk("div", "subcoll", `<div class="label">${esc(name)} is read or written by ${users.length} types · dependencies: ${esc(deps.join(", ") || "none")}</div>`), grid = mk("div", "coll");
    for (const u of users) {
      const t = mk("div", "tile", `<div class="top">${dot(u)}${esc(u.name)}</div><div class="file">${esc(u.path.split("/").pop())}</div>`);
      t.onclick = e => { e.stopPropagation(); select(u.path); };
      grid.append(t);
    }
    sub.append(grid); card.after(sub);
  };
  return card;
}
function drawEntities() {
  roomsEl.replaceChildren(); cards = new Map();
  const names = [...recordNames].sort((a, b) => recordUsers.get(b).length - recordUsers.get(a).length);
  roomsEl.append(mk("div", "sub", `${names.length} record classes. Click a card to list the types that mention it. Filter by record, dependency or type name.`));
  const grid = mk("div", "coll"); names.forEach(n => grid.append(entityCard(n))); roomsEl.append(grid);
  document.getElementById("q").oninput();
}
function depCard(key) {
  const users = depUsers.get(key), d = depDecl.get(key), kits = d ? frameworksOf(key, d) : [];
  const card = mk("div", "tile depcard", `<div class="top">${esc(key)}</div><div class="foot"><span>${esc(d ? d.type : "from a library")}</span><span class="more">${users.length} ›</span></div><div class="file">${esc(d ? kits.join(" · ") || "no framework" : "")}</div>`);
  card.dataset.text = [key, d?.type, ...kits, ...users.map(u => u.name)].join(" ").toLowerCase();
  card.onclick = () => {
    const next = card.nextElementSibling;
    if (next?.classList.contains("subcoll")) { next.remove(); card.classList.remove("open"); return; }
    card.classList.add("open");
    const sub = mk("div", "subcoll", `<div class="label">${esc(key)} is used by ${users.length}</div>`), grid = mk("div", "coll");
    for (const u of users) {
      const t = mk("div", "tile", `<div class="top">${dot(u)}${esc(u.name)}</div><div class="file">${esc(u.path.split("/").pop())}</div>`);
      t.onclick = e => { e.stopPropagation(); select(u.path); };
      grid.append(t);
    }
    sub.append(grid); card.after(sub);
  };
  return card;
}
function drawDeps() {
  roomsEl.replaceChildren(); cards = new Map();
  const keys = [...depUsers.keys()].sort((a, b) => depUsers.get(b).length - depUsers.get(a).length);
  const own = keys.filter(k => depDecl.has(k)), lib = keys.filter(k => !depDecl.has(k));
  roomsEl.append(mk("div", "sub", `${own.length} app dependencies and ${lib.length} from libraries. Click a card to list who uses it. The last line shows the frameworks imported by the file that declares it.`));
  for (const [title, list] of [["App dependencies", own], ["From libraries (clock, uuid...)", lib]]) {
    if (!list.length) continue;
    roomsEl.append(mk("h2", "", title));
    const grid = mk("div", "coll"); list.forEach(k => grid.append(depCard(k))); roomsEl.append(grid);
  }
  document.getElementById("q").oninput();
}
// A leading "!" inverts the filter: "!coredata" lists the dependencies that do not touch Core Data.
function filterDeps(q) {
  const not = q.startsWith("!"), word = not ? q.slice(1) : q;
  for (const c of document.querySelectorAll(".depcard")) {
    const hide = !!word && c.dataset.text.includes(word) === not;
    c.classList.toggle("hide", hide);
    if (c.nextElementSibling?.classList.contains("subcoll")) c.nextElementSibling.classList.toggle("hide", hide);
  }
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
  if (modeEl.value === "deps" || modeEl.value === "entities") return filterDeps(q);
  for (const f of files) cards.get(f.path)?.classList.toggle("hide", q && !(f.path + " " + (NAMES[roomOf(f.path)]?.name ?? "") + " " + (FEATURE_OF[f.path] ?? "") + " " + f.types.map(t => t.name).join(" ")).toLowerCase().includes(q));
};
draw("folder");
</script></body></html>
"""#
