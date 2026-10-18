// PolyMint ledger dashboard — reads the public `plastic_transactions` ledger
// (read-only; Firestore rules make it append-only) and lets an operator or
// auditor see what was recovered, which batches need review, and the
// physical-presence proof behind each credit.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import {
  getFirestore, collection, query, orderBy, limit, onSnapshot,
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

// Same project as the app (lib/firebase_options.dart, web options).
const firebaseConfig = {
  apiKey: "AIzaSyCCmufi-Pc1qacjoa90Cgoqj2n__Nz10l0",
  appId: "1:560821610298:web:33ff6172dc0987e389d203",
  messagingSenderId: "560821610298",
  projectId: "poly-mint",
  authDomain: "poly-mint.firebaseapp.com",
  storageBucket: "poly-mint.firebasestorage.app",
};

const MATERIALS = {
  "1-PET": { short: "PET", name: "Polyethylene terephthalate" },
  "2-HDPE": { short: "HDPE", name: "High-density polyethylene" },
  "3-PVC": { short: "PVC", name: "Polyvinyl chloride" },
  "4-LDPE": { short: "LDPE", name: "Low-density polyethylene" },
  "5-PP": { short: "PP", name: "Polypropylene" },
  "6-PS": { short: "PS", name: "Polystyrene" },
  "7-Other": { short: "Other", name: "Mixed or unidentified plastic" },
};
const material = (code) => MATERIALS[code] ?? { short: code ?? "?", name: "Unknown material" };
const resinNo = (code) => (code && /^\d/.test(code) ? code.split("-")[0] : "?");

const PAGE_SIZE = 25;
const state = {
  all: [],
  range: "all",
  material: "",
  check: "",
  search: "",
  showDemo: false,
  tab: "all",
  sort: { key: "time", dir: -1 },
  page: 0,
};

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : Number(v) || 0);
const fmtKg = (v) => (v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2));
const fmtPct = (v) => `${Math.round(v * 100)}%`;
const dateFmt = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", year: "numeric" });
const timeFmt = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const dayFmt = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short" });

// ---------------------------------------------------------------- normalise
// The ledger holds several schema generations; map them onto one shape.
function normalise(id, d) {
  const ts = d.timestamp?.toDate ? d.timestamp.toDate() : d.timestamp ? new Date(d.timestamp) : null;
  const code = d.polymer_type || "7-Other";
  const aiCode = d.ai_polymer || null;
  const status = String(d.status || "").toLowerCase();

  let check = "legacy";
  if (d.verification === "AI_VERIFIED") check = "ai";
  else if (d.verification === "MANUAL_REVIEW") check = "review";
  else if (d.manual_override === true || status === "flagged") check = "review";

  let reviewReason = "";
  if (check === "review") {
    if (aiCode && aiCode !== code) reviewReason = "override";
    else if (d.manual_override === true) reviewReason = "override";
    else reviewReason = "lowConfidence";
  }

  const popp = d.popp && typeof d.popp === "object" ? d.popp : null;
  let proof = "none";
  if (popp) proof = popp.verdict === "PASS" ? (popp.simulated ? "simulated" : "pass") : "fail";

  return {
    id: d.client_id || id,
    docId: id,
    time: ts,
    user: d.user_name || "Unnamed collector",
    userId: d.user_id || "",
    code,
    weight: num(d.weight_kg),
    credits: num(d.credits_minted),
    co2: num(d.co2_saved_kg),
    confidence: num(d.confidence),
    aiCode,
    aiConf: d.ai_confidence != null ? num(d.ai_confidence) : null,
    top3: Array.isArray(d.ai_top3) ? d.ai_top3 : null,
    check,
    reviewReason,
    status,
    popp,
    proof,
    model: d.model_version || d.model || null,
    appVersion: d.app_version || null,
    inferenceMs: d.inference_ms ?? null,
    geo: d.geolocation && d.geolocation.lat != null ? d.geolocation : null,
    thumb: d.thumb_b64 || null,
    demo: Boolean(d.demo_seed),
  };
}

// ---------------------------------------------------------------- filtering
function baseRecords() {
  const now = Date.now();
  const days = state.range === "all" ? null : Number(state.range);
  const q = state.search.trim().toLowerCase();
  return state.all.filter((r) => {
    if (!state.showDemo && r.demo) return false;
    if (days && (!r.time || now - r.time.getTime() > days * 864e5)) return false;
    if (state.material && r.code !== state.material) return false;
    if (state.check && r.check !== state.check) return false;
    if (q) {
      const hay = `${r.user} ${material(r.code).short} ${material(r.code).name} ${r.id}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
}

const SORTERS = {
  time: (r) => r.time?.getTime() ?? 0,
  user: (r) => r.user.toLowerCase(),
  material: (r) => material(r.code).short,
  weight: (r) => r.weight,
  credits: (r) => r.credits,
  aiConf: (r) => r.aiConf ?? -1,
  check: (r) => ({ review: 0, ai: 1, legacy: 2 }[r.check]),
  proof: (r) => ({ fail: 0, none: 1, simulated: 2, pass: 3 }[r.proof]),
};

// ---------------------------------------------------------------- render
function render() {
  const records = baseRecords();
  const reviewCount = records.filter((r) => r.check === "review").length;
  $("count-all").textContent = records.length;
  $("count-review").textContent = reviewCount;
  renderSummary(records, reviewCount);
  renderTimeChart(records);
  renderMaterialChart(records);
  renderTable(state.tab === "review" ? records.filter((r) => r.check === "review") : records);
}

function renderSummary(records, reviewCount) {
  const kg = records.reduce((a, r) => a + r.weight, 0);
  const credits = records.reduce((a, r) => a + r.credits, 0);
  const co2 = records.reduce((a, r) => a + r.co2, 0);
  const checked = records.filter((r) => r.check !== "legacy");
  const ai = checked.filter((r) => r.check === "ai").length;
  const period = { all: "", 7: " in the last 7 days", 30: " in the last 30 days", 90: " in the last 90 days" }[state.range];

  if (!records.length) {
    $("summary").textContent = state.all.length
      ? "No batches match these filters."
      : "No batches have been recorded yet. Scan a batch in the app to start the ledger.";
  } else {
    $("summary").innerHTML =
      `<span class="num">${fmtKg(kg)}</span> kg of plastic recovered in ` +
      `<span class="num">${records.length}</span> ${records.length === 1 ? "batch" : "batches"}${period}. ` +
      (reviewCount
        ? `<span class="num">${reviewCount}</span> ${reviewCount === 1 ? "needs" : "need"} review.`
        : "None need review.");
  }

  const readout = (label, value, unit = "") =>
    `<div><dt>${label}</dt><dd>${value}${unit ? `<small>${unit}</small>` : ""}</dd></div>`;
  $("readouts").innerHTML =
    readout("Plastic recovered", fmtKg(kg), "kg") +
    readout("Credits minted", credits.toFixed(2)) +
    readout("CO₂e avoided", fmtKg(co2), "kg") +
    readout("Batches", records.length) +
    readout("Confirmed by AI", checked.length ? fmtPct(ai / checked.length) : "—",
      checked.length ? `of ${checked.length} checked` : "");
}

// --- charts (hand-built SVG: single hue, labelled axes, hover tooltips) ---
const tip = $("tooltip");
function showTip(evt, html) {
  tip.innerHTML = html;
  tip.hidden = false;
  const { clientX: x, clientY: y } = evt.touches?.[0] ?? evt;
  const w = tip.offsetWidth, h = tip.offsetHeight;
  tip.style.left = `${Math.min(window.innerWidth - w - 8, Math.max(8, x - w / 2))}px`;
  tip.style.top = `${y - h - 14 < 8 ? y + 18 : y - h - 14}px`;
}
const hideTip = () => { tip.hidden = true; };

function niceMax(v) {
  if (v <= 0) return 1;
  const p = 10 ** Math.floor(Math.log10(v));
  const n = v / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
}

function topRoundedBar(x, y, w, h, r = 4) {
  if (h <= 0) return "";
  r = Math.min(r, w / 2, h);
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}
function rightRoundedBar(x, y, w, h, r = 4) {
  if (w <= 0) return "";
  r = Math.min(r, h / 2, w);
  return `M${x},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h - r}Q${x + w},${y + h} ${x + w - r},${y + h}H${x}Z`;
}

function renderTimeChart(records) {
  const body = $("chart-time").querySelector(".chart-body");
  const dated = records.filter((r) => r.time);
  if (!dated.length) { body.innerHTML = `<div class="chart-empty">Nothing recovered in this period.</div>`; return; }

  const dayKey = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const end = dayKey(new Date());
  const start = state.range === "all"
    ? dayKey(new Date(Math.min(...dated.map((r) => r.time.getTime()))))
    : end - (Number(state.range) - 1) * 864e5;
  const spanDays = Math.round((end - start) / 864e5) + 1;
  const weekly = spanDays > 92;
  const step = (weekly ? 7 : 1) * 864e5;
  const buckets = [];
  for (let t = start; t <= end; t += step) buckets.push({ t, kg: 0, n: 0 });
  for (const r of dated) {
    const i = Math.min(buckets.length - 1, Math.floor((dayKey(r.time) - start) / step));
    if (i >= 0) { buckets[i].kg += r.weight; buckets[i].n += 1; }
  }
  $("chart-time").querySelector(".chart-title").textContent =
    weekly ? "Plastic recovered per week" : "Plastic recovered per day";

  const W = Math.max(300, body.clientWidth || 640), H = W < 480 ? 200 : 230, m = { t: 10, r: 8, b: 26, l: 40 };
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const max = niceMax(Math.max(...buckets.map((b) => b.kg)));
  const bw = iw / buckets.length;
  const barW = Math.max(1.5, Math.min(28, bw - 2));
  const ticks = [0, max / 2, max];
  const labelEvery = Math.ceil(buckets.length / Math.max(3, Math.floor(iw / 90)));

  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Plastic recovered over time, in kilograms">`;
  svg += `<g class="grid">${ticks.map((v) => `<line x1="${m.l}" x2="${W - m.r}" y1="${m.t + ih - (v / max) * ih}" y2="${m.t + ih - (v / max) * ih}"/>`).join("")}</g>`;
  svg += `<g class="axis">${ticks.map((v) => `<text x="${m.l - 6}" y="${m.t + ih - (v / max) * ih + 4}" text-anchor="end">${fmtKg(v)}</text>`).join("")}`;
  buckets.forEach((b, i) => {
    if (i % labelEvery === 0) svg += `<text x="${m.l + i * bw + bw / 2}" y="${H - 6}" text-anchor="middle">${dayFmt.format(new Date(b.t))}</text>`;
  });
  svg += `</g>`;
  buckets.forEach((b, i) => {
    const h = (b.kg / max) * ih;
    const x = m.l + i * bw + (bw - barW) / 2;
    const label = `${weekly ? "Week of " : ""}${dateFmt.format(new Date(b.t))}`;
    svg += `<rect class="hit" x="${m.l + i * bw}" y="${m.t}" width="${bw}" height="${ih}" data-tip="${esc(`${label}<br><b>${fmtKg(b.kg)} kg</b> · ${b.n} ${b.n === 1 ? "batch" : "batches"}`)}"/>`;
    svg += `<path class="bar" d="${topRoundedBar(x, m.t + ih - h, barW, h)}"/>`;
  });
  svg += `</svg>`;
  body.innerHTML = svg;
  bindTips(body);
}

function renderMaterialChart(records) {
  const body = $("chart-material").querySelector(".chart-body");
  const by = {};
  for (const r of records) {
    by[r.code] ??= { kg: 0, n: 0 };
    by[r.code].kg += r.weight;
    by[r.code].n += 1;
  }
  const rows = Object.entries(by).sort((a, b) => b[1].kg - a[1].kg);
  if (!rows.length) { body.innerHTML = `<div class="chart-empty">No materials to show.</div>`; return; }

  const W = Math.max(280, body.clientWidth || 420), rowH = 34, m = { l: 64, r: 56 };
  const H = rows.length * rowH + 4;
  const iw = W - m.l - m.r;
  const max = Math.max(...rows.map(([, v]) => v.kg)) || 1;
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Plastic recovered by material, in kilograms">`;
  rows.forEach(([code, v], i) => {
    const y = i * rowH + 6;
    const w = (v.kg / max) * iw;
    const active = state.material === code ? " active" : "";
    svg += `<text class="label" x="0" y="${y + 15}">${esc(material(code).short)}</text>`;
    svg += `<rect class="hit" x="0" y="${y - 4}" width="${W}" height="${rowH - 2}" data-code="${esc(code)}" data-tip="${esc(`${material(code).name}<br><b>${fmtKg(v.kg)} kg</b> · ${v.n} ${v.n === 1 ? "batch" : "batches"}<br>Click to filter`)}"/>`;
    svg += `<path class="bar${active}" d="${rightRoundedBar(m.l, y + 2, Math.max(w, 2), 18)}"/>`;
    svg += `<text class="value" x="${m.l + Math.max(w, 2) + 8}" y="${y + 15}">${fmtKg(v.kg)}</text>`;
  });
  svg += `</svg>`;
  body.innerHTML = svg;
  bindTips(body);
  body.querySelectorAll(".hit[data-code]").forEach((el) => el.addEventListener("click", () => {
    state.material = state.material === el.dataset.code ? "" : el.dataset.code;
    $("f-material").value = state.material;
    state.page = 0;
    render();
  }));
}

function bindTips(root) {
  root.querySelectorAll("[data-tip]").forEach((el) => {
    el.addEventListener("mousemove", (e) => showTip(e, el.dataset.tip));
    el.addEventListener("mouseleave", hideTip);
    el.addEventListener("touchstart", (e) => showTip(e, el.dataset.tip), { passive: true });
  });
}

// --- table ---
const ICONS = {
  ai: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="currentColor"/><path d="M4.6 8.2 7 10.5l4.4-4.6" stroke="#fff" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  review: `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.5 15 14H1z" fill="currentColor"/><path d="M8 6v3.6M8 11.4v.1" stroke="#fff" stroke-width="1.7" stroke-linecap="round"/></svg>`,
  legacy: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2.5 2.2"/></svg>`,
  fail: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="currentColor"/><path d="M5.4 5.4l5.2 5.2M10.6 5.4l-5.2 5.2" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>`,
};
const CHECK_LABEL = { ai: "AI-verified", review: "Needs review", legacy: "Not recorded" };
const checkBadge = (c) => `<span class="badge ${c}">${ICONS[c]}${CHECK_LABEL[c]}</span>`;
function proofBadge(p) {
  if (p === "pass") return `<span class="badge ai">${ICONS.ai}Weight matched</span>`;
  if (p === "simulated") return `<span class="badge legacy">${ICONS.ai}Simulated scale</span>`;
  if (p === "fail") return `<span class="badge fail">${ICONS.fail}Failed</span>`;
  return `<span class="badge legacy">${ICONS.legacy}No proof stored</span>`;
}

function renderTable(rows) {
  const { key, dir } = state.sort;
  const f = SORTERS[key];
  rows = [...rows].sort((a, b) => (f(a) > f(b) ? 1 : f(a) < f(b) ? -1 : 0) * dir);
  const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  state.page = Math.min(state.page, pages - 1);
  const slice = rows.slice(state.page * PAGE_SIZE, (state.page + 1) * PAGE_SIZE);

  $("rows").innerHTML = slice.map((r) => {
    const mat = material(r.code);
    const ai = r.aiCode && r.aiCode !== r.code
      ? `<span class="muted">AI said</span> ${esc(material(r.aiCode).short)} ${r.aiConf != null ? fmtPct(r.aiConf) : ""}`
      : r.aiConf != null ? fmtPct(r.aiConf) : `<span class="muted">${fmtPct(r.confidence)}</span>`;
    return `<tr tabindex="0" data-id="${esc(r.docId)}">
      <td class="c-time">${r.time ? timeFmt.format(r.time) : "—"}</td>
      <td class="c-user">${esc(r.user)}${r.demo ? `<span class="demo-tag">demo</span>` : ""}</td>
      <td class="c-mat"><span class="resin">${resinNo(r.code)}</span>${esc(mat.short)}</td>
      <td class="num c-weight">${r.weight.toFixed(2)} kg</td>
      <td class="num c-credits">${r.credits.toFixed(2)}</td>
      <td class="num c-ai">${ai}</td>
      <td class="c-check">${checkBadge(r.check)}</td>
      <td class="c-proof">${proofBadge(r.proof)}</td>
    </tr>`;
  }).join("");

  const empty = $("empty");
  if (!rows.length) {
    empty.hidden = false;
    empty.innerHTML = state.tab === "review"
      ? `Nothing needs review for these filters.`
      : `No records match these filters.<br><button class="btn ghost" type="button" id="empty-clear">Clear filters</button>`;
    $("empty-clear")?.addEventListener("click", clearFilters);
  } else {
    empty.hidden = true;
  }

  $("pager").innerHTML = rows.length > PAGE_SIZE
    ? `<span>Showing ${state.page * PAGE_SIZE + 1}–${Math.min(rows.length, (state.page + 1) * PAGE_SIZE)} of ${rows.length}</span>
       <span class="btns"><button class="btn ghost" id="prev" ${state.page === 0 ? "disabled" : ""}>Previous</button>
       <button class="btn ghost" id="next" ${state.page >= pages - 1 ? "disabled" : ""}>Next</button></span>`
    : rows.length ? `<span>${rows.length} ${rows.length === 1 ? "record" : "records"}</span>` : "";
  $("prev")?.addEventListener("click", () => { state.page--; render(); });
  $("next")?.addEventListener("click", () => { state.page++; render(); });

  document.querySelectorAll(".table th").forEach((th) => {
    th.setAttribute("aria-sort", th.dataset.sort === key ? (dir > 0 ? "ascending" : "descending") : "none");
  });
}

// ---------------------------------------------------------------- drawer
let lastFocus = null;
function openDrawer(docId) {
  const r = state.all.find((x) => x.docId === docId);
  if (!r) return;
  lastFocus = document.activeElement;
  const mat = material(r.code);
  $("d-title").textContent = `${mat.short} · ${r.weight.toFixed(2)} kg`;
  $("d-sub").textContent = `${r.time ? dateFmt.format(r.time) + ", " + timeFmt.format(r.time).split(", ").pop() : "Time not recorded"} — ${r.user}`;

  const sections = [];
  if (r.thumb) sections.push(`<img class="d-photo" alt="Photo of the batch" src="data:image/jpeg;base64,${esc(r.thumb)}">`);

  // Verification
  let callout;
  if (r.check === "ai") callout = `<div class="callout ai">The AI identified ${esc(mat.short)} with ${fmtPct(r.aiConf ?? r.confidence)} confidence, above the 85% gate.</div>`;
  else if (r.check === "review") {
    callout = r.reviewReason === "override"
      ? `<div class="callout review">The collector recorded ${esc(mat.short)}, but the AI's pick was ${esc(material(r.aiCode).short)}${r.aiConf != null ? ` (${fmtPct(r.aiConf)})` : ""}. Check the photo before relying on these credits.</div>`
      : `<div class="callout review">The AI was only ${fmtPct(r.aiConf ?? r.confidence)} sure this is ${esc(mat.short)}, below the 85% gate. Check the photo before relying on these credits.</div>`;
  } else callout = `<div class="callout">This record was written before the app stored how the material was verified.</div>`;
  let probs = "";
  if (r.top3?.length) {
    probs = `<div class="probs">${r.top3.map((p) => `
      <div class="prob ${p.code === r.code ? "picked" : ""}">
        <span>${esc(material(p.code).short)}</span>
        <span class="prob-track"><span class="prob-fill" style="width:${(num(p.p) * 100).toFixed(1)}%"></span></span>
        <span class="mono">${fmtPct(num(p.p))}</span>
      </div>`).join("")}</div>`;
  }
  sections.push(`<section class="d-section"><h3>Material check</h3>${checkBadge(r.check)}<div style="height:10px"></div>${callout}${probs}</section>`);

  // Scale proof
  if (r.popp) {
    const p = r.popp;
    const win = Math.max(1, num(p.stableWindowMs));
    const off = Math.min(win, Math.max(0, num(p.captureOffsetMs)));
    const verdict = r.proof === "fail"
      ? `The photo did not match a steady weight on the scale (${esc(p.verdict)}).`
      : `The photo was taken ${(off / 1000).toFixed(1)} s into a ${(win / 1000).toFixed(1)} s window in which the scale held steady.${p.simulated ? " This reading came from the simulated scale, not hardware." : ""}`;
    sections.push(`<section class="d-section"><h3>Scale proof</h3>${proofBadge(r.proof)}
      <p class="verdict-line" style="margin-top:10px">${verdict}</p>
      ${r.proof !== "fail" ? `<div class="popp-track" aria-hidden="true"><div class="popp-rail"></div><div class="popp-window" style="left:0;width:100%"></div><div class="popp-capture" style="left:${(off / win) * 100}%"></div></div>
      <div class="popp-scale"><span>0 s</span><span>${(win / 1000).toFixed(1)} s steady</span></div>` : ""}
      <dl class="kv" style="margin-top:14px">
        <dt>Weight added</dt><dd class="mono">${num(p.settleDeltaKg).toFixed(3)} kg</dd>
        <dt>Readings hashed</dt><dd class="mono">${num(p.sampleCount)}</dd>
        <dt>Hash chain</dt><dd class="hash">${esc(p.sampleHashChain || "—")}</dd>
      </dl></section>`);
  } else {
    sections.push(`<section class="d-section"><h3>Scale proof</h3>${proofBadge("none")}<p class="verdict-line muted" style="margin-top:10px">No physical-presence proof was stored with this record.</p></section>`);
  }

  // Details
  const kv = [
    ["Credits minted", `<span class="mono">${r.credits.toFixed(2)}</span>`],
    ["CO₂e avoided", `<span class="mono">${r.co2.toFixed(2)} kg</span>`],
    ["Material", `${esc(mat.short)} — ${esc(mat.name)}`],
    ["Model", r.model ? `<span class="mono">${esc(r.model)}</span>` : "—"],
    ["Location", r.geo ? `<a href="https://www.openstreetmap.org/?mlat=${num(r.geo.lat)}&mlon=${num(r.geo.lng)}#map=17/${num(r.geo.lat)}/${num(r.geo.lng)}" target="_blank" rel="noopener">${num(r.geo.lat).toFixed(4)}, ${num(r.geo.lng).toFixed(4)}</a>` : "Not recorded"],
    ["Collector ID", r.userId ? `<span class="mono">${esc(r.userId)}</span>` : "—"],
    ["Record ID", `<span class="mono">${esc(r.id)}</span>`],
  ];
  if (r.appVersion) kv.push(["App version", `<span class="mono">${esc(r.appVersion)}</span>`]);
  if (r.inferenceMs != null) kv.push(["Inference time", `<span class="mono">${esc(r.inferenceMs)} ms</span>`]);
  if (r.demo) kv.push(["Origin", "Demo seed data, not a real recovery"]);
  sections.push(`<section class="d-section"><h3>Record</h3><dl class="kv">${kv.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("")}</dl></section>`);

  $("d-body").innerHTML = sections.join("");
  const drawer = $("drawer");
  drawer.setAttribute("aria-hidden", "false");
  drawer.querySelector(".drawer-panel").focus();
}
function closeDrawer() {
  $("drawer").setAttribute("aria-hidden", "true");
  lastFocus?.focus?.();
}

// ---------------------------------------------------------------- export
function exportCsv() {
  const rows = baseRecords().filter((r) => state.tab !== "review" || r.check === "review");
  const head = ["recorded_at", "collector", "collector_id", "material", "weight_kg", "credits", "co2e_kg",
    "ai_pick", "ai_confidence", "verification", "scale_proof", "model", "lat", "lng", "record_id", "demo"];
  const cell = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
  const lines = rows.map((r) => [
    r.time?.toISOString(), r.user, r.userId, material(r.code).short, r.weight, r.credits, r.co2,
    r.aiCode ? material(r.aiCode).short : "", r.aiConf ?? "", CHECK_LABEL[r.check], r.proof, r.model,
    r.geo?.lat, r.geo?.lng, r.id, r.demo ? "yes" : "no",
  ].map(cell).join(","));
  const blob = new Blob([[head.join(","), ...lines].join("\n")], { type: "text/csv" });
  const a = Object.assign(document.createElement("a"), {
    href: URL.createObjectURL(blob),
    download: `polymint-ledger-${new Date().toISOString().slice(0, 10)}.csv`,
  });
  a.click();
  URL.revokeObjectURL(a.href);
}

// ---------------------------------------------------------------- wiring
function clearFilters() {
  Object.assign(state, { range: "all", material: "", check: "", search: "", page: 0 });
  $("f-range").value = "all"; $("f-material").value = ""; $("f-check").value = ""; $("f-search").value = "";
  render();
}

function populateMaterials() {
  $("f-material").innerHTML = `<option value="">All materials</option>` +
    Object.entries(MATERIALS).map(([code, m]) => `<option value="${code}">${m.short} — ${m.name}</option>`).join("");
}

function setTheme(t) {
  if (t) document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme;
  try { t ? localStorage.setItem("pm-theme", t) : localStorage.removeItem("pm-theme"); } catch {}
}

function wire() {
  populateMaterials();
  try { const t = localStorage.getItem("pm-theme"); if (t) setTheme(t); } catch {}
  $("theme").addEventListener("click", () => {
    const dark = document.documentElement.dataset.theme
      ? document.documentElement.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    setTheme(dark ? "light" : "dark");
  });
  const on = (id, ev, fn) => $(id).addEventListener(ev, fn);
  on("f-range", "change", (e) => { state.range = e.target.value; state.page = 0; render(); });
  on("f-material", "change", (e) => { state.material = e.target.value; state.page = 0; render(); });
  on("f-check", "change", (e) => { state.check = e.target.value; state.page = 0; render(); });
  on("f-search", "input", (e) => { state.search = e.target.value; state.page = 0; render(); });
  on("show-demo", "change", (e) => { state.showDemo = e.target.checked; state.page = 0; render(); });
  on("clear", "click", clearFilters);
  on("export", "click", exportCsv);

  document.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => {
    state.tab = t.dataset.tab;
    state.page = 0;
    document.querySelectorAll(".tab").forEach((x) => x.setAttribute("aria-selected", String(x === t)));
    $("tab-help").hidden = state.tab !== "review";
    render();
  }));
  document.querySelectorAll(".table th").forEach((th) => th.addEventListener("click", () => {
    const k = th.dataset.sort;
    state.sort = { key: k, dir: state.sort.key === k ? -state.sort.dir : (k === "user" || k === "material" ? 1 : -1) };
    render();
  }));
  $("rows").addEventListener("click", (e) => { const tr = e.target.closest("tr[data-id]"); if (tr) openDrawer(tr.dataset.id); });
  $("rows").addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") { const tr = e.target.closest("tr[data-id]"); if (tr) { e.preventDefault(); openDrawer(tr.dataset.id); } }
  });
  $("drawer").addEventListener("click", (e) => { if (e.target.closest("[data-close]")) closeDrawer(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && $("drawer").getAttribute("aria-hidden") === "false") closeDrawer(); });
}

// #preview loads sample records in the current schema (no Firestore), so the
// review and scale-proof views can be checked before real batches exist.
async function loadPreview() {
  const live = $("live");
  const res = await fetch("preview-records.json");
  const rows = await res.json();
  state.all = rows.map((d, i) => normalise(`preview-${i}`, { ...d, timestamp: new Date(d.timestamp) }));
  state.showDemo = true;
  $("show-demo").checked = true;
  live.className = "live preview";
  $("live-text").textContent = `Preview data · ${state.all.length} sample records`;
  render();
}

function connect() {
  if (location.hash === "#preview") { loadPreview(); return; }
  const live = $("live");
  try {
    const db = getFirestore(initializeApp(firebaseConfig));
    const q = query(collection(db, "plastic_transactions"), orderBy("timestamp", "desc"), limit(5000));
    onSnapshot(q, (snap) => {
      state.all = snap.docs.map((d) => normalise(d.id, d.data()));
      live.className = "live on";
      $("live-text").textContent = `Live · ${state.all.length} records in ledger`;
      render();
    }, (err) => {
      live.className = "live err";
      $("live-text").textContent = "Can't reach the ledger";
      $("summary").textContent = `The ledger could not be loaded (${err.code || err.message}). Check your connection and reload.`;
    });
  } catch (err) {
    live.className = "live err";
    $("live-text").textContent = "Can't reach the ledger";
    $("summary").textContent = `The dashboard could not start: ${err.message}`;
  }
}

let resizeTimer;
addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(render, 150); });

wire();
connect();
