// The "Graph" option: every node of the current view on one canvas. Plain code, no library, no network.
let graphScript = #"""
// One force-directed graph per view. Nodes repel each other, links pull their ends together, the canvas pans and zooms.
// ponytail: every node repels every other one (O(n²) per step). Fine for a few thousand nodes; use a grid or quadtree beyond that.
const graphToggle = document.getElementById("graphToggle"), groupsEl = document.getElementById("groups"), sideEl = document.getElementById("side");
const graph = { sel: null, stop: 0, paint: null, onClear: null };
const hueOf = key => { let h = 0; for (const ch of key) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return PALETTE[h % PALETTE.length]; };
const featureColor = path => { const i = FEATURES.findIndex(x => x.name === FEATURE_OF[path]); return i < 0 ? "#c7c7cc" : PALETTE[i % PALETTE.length]; };
const VIA_COLOR = { scope: "#34c759", ifLet: "#007aff", forEach: "#af52de", body: "#8e8e93", enumCase: "#ff9500" };
const KEY_COLOR = "#1d1d1f";
// Nodes and links of the current view. A node is { id, label, color, text, pick? }; "text" is what the filter searches.
// Each file-like node also has a "group": its folder in the folder view, its feature in every other view.
function graphData(mode) {
  const kind = mode === "folder" ? "folder" : "feature", groupOf = path => kind === "folder" ? roomOf(path) : (FEATURE_OF[path] ?? UNASSIGNED);
  const nodes = new Map(), links = [];
  const node = (id, label, color, extra = {}) => { if (!nodes.has(id)) nodes.set(id, { id, label, color, text: label.toLowerCase(), ...extra }); return nodes.get(id); };
  const link = (a, b, color = "#8e8e93") => links.push({ a, b, color });
  const typeNode = u => node(u.path + "#" + u.name, u.name, featureColor(u.path), { group: groupOf(u.path), text: (u.name + " " + u.path).toLowerCase(), pick: () => select(u.path) });
  if (mode === "tree") {
    for (const r of reducers) node(r.name, r.name, featureColor(r.path), { group: groupOf(r.path), text: reducerText(r), pick: () => selectReducer(r, mk("div", "")) });
    for (const r of reducers) for (const c of kidsOf(r)) link(r.name, c.child, VIA_COLOR[c.via]);
  } else if (mode === "deps" || mode === "entities") {
    const owners = mode === "deps" ? depUsers : new Map([...recordUsers].filter(([, u]) => u.length));
    for (const [key, users] of owners) {
      node("k:" + key, key, KEY_COLOR, { big: true });
      for (const u of users) link(typeNode(u).id, "k:" + key);
    }
  } else {
    for (const f of orphanToggle.checked ? files.filter(isOrphan) : files) node(f.path, f.path.split("/").pop(), mode === "feature" ? featureColor(f.path) : hueOf(roomOf(f.path)), { group: groupOf(f.path), text: (f.path + " " + (FEATURE_OF[f.path] ?? "") + " " + f.types.map(t => t.name).join(" ")).toLowerCase(), pick: () => select(f.path) });
    for (const [from, set] of uses) for (const to of set) link(from, to);
  }
  return { nodes: [...nodes.values()], links: links.filter(l => nodes.has(l.a) && nodes.has(l.b)), kind };
}
// Moves the nodes a little every frame until they settle. Calling it again stops the previous run.
function layout(nodes, links, onTick) {
  const index = new Map(nodes.map((n, i) => [n.id, i]));
  const pairs = links.map(l => [index.get(l.a), index.get(l.b)]).filter(([a, b]) => a !== undefined && b !== undefined);
  nodes.forEach((n, i) => { const a = i * 2.4, r = 12 * Math.sqrt(i); Object.assign(n, { x: r * Math.cos(a), y: r * Math.sin(a), vx: 0, vy: 0, deg: 0 }); });
  for (const [a, b] of pairs) { nodes[a].deg++; nodes[b].deg++; }
  let alpha = 1;
  const my = ++graph.stop;
  const tick = () => {
    for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) {
      const p = nodes[i], q = nodes[j], dx = q.x - p.x, dy = q.y - p.y, d2 = dx * dx + dy * dy + 0.01, f = 30 * alpha / d2;
      p.vx -= dx * f; p.vy -= dy * f; q.vx += dx * f; q.vy += dy * f;
    }
    for (const [a, b] of pairs) {
      const p = nodes[a], q = nodes[b], dx = q.x - p.x, dy = q.y - p.y, d = Math.sqrt(dx * dx + dy * dy) + 0.01;
      const k = (d - 30) / d * alpha / Math.min(p.deg, q.deg);
      p.vx += dx * k * 0.5; p.vy += dy * k * 0.5; q.vx -= dx * k * 0.5; q.vy -= dy * k * 0.5;
    }
    for (const n of nodes) { n.vx = (n.vx - n.x * 0.02 * alpha) * 0.6; n.vy = (n.vy - n.y * 0.02 * alpha) * 0.6; n.x += n.vx; n.y += n.vy; }
    alpha *= 0.985;
  };
  const frame = () => {
    if (my !== graph.stop) return;
    for (let k = 0; k < 8 && alpha > 0.02; k++) tick();
    onTick(alpha > 0.02);
    if (alpha > 0.02) requestAnimationFrame(frame);
  };
  frame();
}
// The group filter above the graph. Returns { has(node), showLinked() }: a node is lit when its group is checked. A node with
// no group (a dependency key or a record) is lit when one of its neighbours is. Groups linked to the checked ones are listed
// in the sidebar while no node is selected; a selected node takes the sidebar over until the canvas background is clicked.
function groupSelection(nodes, links, kind, byId, near, repaint) {
  const members = new Map();
  for (const n of nodes) if (n.group !== undefined) { if (!members.has(n.group)) members.set(n.group, []); members.get(n.group).push(n); }
  const chosen = new Set(members.keys());
  const label = g => kind === "folder" && NAMES[g] ? `${NAMES[g].name} (${g})` : g;
  let linkedHtml = "";
  const byName = (a, b) => label(a).localeCompare(label(b), undefined, { sensitivity: "base" });
  const render = () => {
    const linked = new Map();
    for (const l of links) {
      const a = byId.get(l.a), b = byId.get(l.b);
      if (!a || !b || a.group === undefined || b.group === undefined || a.group === b.group) continue;
      for (const [x, y] of [[a, b], [b, a]]) if (chosen.has(x.group) && !chosen.has(y.group)) linked.set(y.group, (linked.get(y.group) ?? 0) + 1);
    }
    const row = g => `<label class="grow"><input type="checkbox" data-g="${esc(g)}" ${chosen.has(g) ? "checked" : ""}><span class="dot" style="background:${members.get(g)[0].color}"></span><span class="gname">${esc(label(g))}</span><code>${members.get(g).length}</code></label>`;
    linkedHtml = linked.size ? `<h2>Linked to the shown ${kind === "folder" ? "folders" : "features"}</h2><div class="glist">${[...linked].sort((a, b) => byName(a[0], b[0])).map(([g, c]) => `<div class="grow"><button data-add="${esc(g)}">Show</button><span class="gname">${esc(label(g))}</span><code>${c} links</code></div>`).join("")}</div>` : "";
    groupsEl.innerHTML = `<h1>${kind === "folder" ? "Folders" : "Features"} <span class="sub">${chosen.size} of ${members.size} shown</span></h1>
      <div class="gbtns"><button data-all="1">Select all</button><button data-all="0">Unselect all</button></div>
      <h2>All ${kind === "folder" ? "folders" : "features"}</h2><div class="glist">${[...members.keys()].sort(byName).map(row).join("")}</div>`;
    showLinked();
  };
  const showLinked = () => { if (graph.sel === null) sideEl.innerHTML = linkedHtml || SIDE_HINT; };
  groupsEl.hidden = members.size < 2;
  groupsEl.onchange = e => { const g = e.target.dataset.g; if (g === undefined) return; e.target.checked ? chosen.add(g) : chosen.delete(g); render(); repaint(); };
  groupsEl.onclick = e => {
    const { all } = e.target.dataset;
    if (all === undefined) return;
    chosen.clear(); if (all === "1") members.forEach((_, g) => chosen.add(g));
    render(); repaint();
  };
  sideEl.onclick = e => { const { add } = e.target.dataset; if (add !== undefined) { chosen.add(add); render(); repaint(); } };
  render();
  graph.onClear = showLinked;
  return { showLinked, has: n => n.group === undefined ? [...near.get(n.id)].some(id => chosen.has(byId.get(id).group)) : chosen.has(n.group) };
}
function drawGraph(mode) {
  const { nodes, links, kind } = graphData(mode);
  graph.sel = null;
  roomsEl.replaceChildren(); cards = new Map();
  roomsEl.append(mk("div", "sub", `${nodes.length} nodes, ${links.length} links. Drag to move, scroll to zoom, hover a node to light up its neighbours, click to open it. The filter box dims what does not match; the group filter hides the other groups.`));
  if (!nodes.length) { graph.stop++; return; }
  const cv = mk("canvas", "graphcv"), ctx = cv.getContext("2d"), dpr = window.devicePixelRatio || 1;
  roomsEl.append(cv);
  const W = cv.clientWidth || roomsEl.clientWidth, H = Math.max(480, innerHeight - 170);
  cv.width = W * dpr; cv.height = H * dpr; cv.style.height = H + "px";
  const view = { k: 1, x: W / 2, y: H / 2, touched: false };
  const byId = new Map(nodes.map(n => [n.id, n])), near = new Map(nodes.map(n => [n.id, new Set()]));
  for (const l of links) if (byId.has(l.a) && byId.has(l.b)) { near.get(l.a).add(l.b); near.get(l.b).add(l.a); }
  let hover = null;
  const shown = groupSelection(nodes, links, kind, byId, near, () => paint());
  const radius = n => (n.big ? 7 : 3) + Math.min(6, Math.sqrt(n.deg ?? 0));
  const paint = () => {
    const q = document.getElementById("q").value.toLowerCase(), live = hover ? near.get(hover.id) : null;
    const on = n => (!q || n.text.includes(q)) && (!hover || n === hover || live.has(n.id));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
    ctx.translate(view.x, view.y); ctx.scale(view.k, view.k);
    ctx.lineWidth = 1 / view.k;
    for (const l of links) {
      const a = byId.get(l.a), b = byId.get(l.b);
      if (!a || !b || !shown.has(a) || !shown.has(b)) continue;
      ctx.globalAlpha = on(a) && on(b) ? (hover ? 0.9 : 0.35) : 0.04;
      ctx.strokeStyle = l.color; ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    for (const n of nodes) {
      if (!shown.has(n)) continue; // nodes outside the checked groups are not drawn at all
      ctx.globalAlpha = on(n) ? 1 : 0.1; ctx.fillStyle = n.color;
      ctx.beginPath(); ctx.arc(n.x, n.y, radius(n), 0, 6.2832); ctx.fill();
      if (n.id === graph.sel) { ctx.strokeStyle = "#ff9500"; ctx.lineWidth = 2 / view.k; ctx.stroke(); ctx.lineWidth = 1 / view.k; }
    }
    // Every shown node carries its name. Names of dimmed nodes fade with them.
    ctx.font = `${11 / view.k}px -apple-system, sans-serif`; ctx.fillStyle = "#1d1d1f";
    for (const n of nodes) {
      if (!shown.has(n)) continue;
      ctx.globalAlpha = on(n) ? 1 : 0.1;
      ctx.fillText(n.label, n.x + radius(n) + 2, n.y + 4 / view.k);
    }
    ctx.globalAlpha = 1;
  };
  graph.paint = paint;
  const fit = () => {
    const xs = nodes.map(n => n.x), ys = nodes.map(n => n.y), x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    view.k = Math.min(3, 0.9 * Math.min(W / (x1 - x0 || 1), H / (y1 - y0 || 1)));
    view.x = W / 2 - view.k * (x0 + x1) / 2; view.y = H / 2 - view.k * (y0 + y1) / 2;
  };
  layout(nodes, links, () => { if (!view.touched) fit(); paint(); });
  const at = e => { const r = cv.getBoundingClientRect(); return [(e.clientX - r.left) * W / r.width, (e.clientY - r.top) * H / r.height]; };
  const find = (mx, my) => {
    const wx = (mx - view.x) / view.k, wy = (my - view.y) / view.k;
    return nodes.find(n => shown.has(n) && (n.x - wx) ** 2 + (n.y - wy) ** 2 <= (radius(n) + 3 / view.k) ** 2) ?? null;
  };
  let drag = null, panned = false; // "panned" outlives the mouse button: the click event comes after mouseup
  cv.onmousedown = e => { panned = false; drag = { from: at(e), x: view.x, y: view.y, moved: false }; };
  window.onmouseup = () => { drag = null; };
  cv.onmousemove = e => {
    const [mx, my] = at(e);
    if (drag) {
      if (Math.hypot(mx - drag.from[0], my - drag.from[1]) > 4) drag.moved = panned = view.touched = true;
      if (drag.moved) { view.x = drag.x + mx - drag.from[0]; view.y = drag.y + my - drag.from[1]; paint(); return; }
    }
    const n = find(mx, my);
    if (n !== hover) { hover = n; cv.style.cursor = n?.pick ? "pointer" : "grab"; paint(); }
  };
  cv.onclick = e => {
    if (panned) return;
    if (!hover) { graph.sel = null; selectedPath = null; shown.showLinked(); paint(); return; } // the background clears the selection
    graph.sel = hover.id; hover.pick?.(); paint();
  };
  cv.onwheel = e => {
    e.preventDefault(); view.touched = true;
    const [mx, my] = at(e), f = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    view.x = mx - (mx - view.x) * f; view.y = my - (my - view.y) * f; view.k *= f; paint();
  };
}
"""#
