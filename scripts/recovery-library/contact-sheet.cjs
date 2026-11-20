#!/usr/bin/env node
//
// Writes output/recovery-library/contact-sheet.html: a grid of every seed
// item's photo with id, name and country. Ids in flagged.json
// ([{id, reason}]) are outlined in red with the reason shown.
//
// Usage: node scripts/recovery-library/contact-sheet.cjs [--out <dir>]
const fs = require("node:fs");
const path = require("node:path");
const {DEFAULT_OUT_DIR, loadSeed, parseFlags} = require("./common.cjs");

const ENTITIES = {
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
};
const escapeHtml = (text) =>
  String(text).replace(/[&<>"']/g, (ch) => ENTITIES[ch]);

/**
 * @param {string} dir
 * @return {Map<string, string>} flagged id -> reason.
 */
function loadFlagged(dir) {
  const file = path.join(dir, "flagged.json");
  if (!fs.existsSync(file)) return new Map();
  return new Map(JSON.parse(fs.readFileSync(file, "utf8"))
      .map(({id, reason}) => [id, reason ?? ""]));
}

/**
 * The self-contained sheet HTML (relative image paths).
 * @param {object[]} seed
 * @param {Map<string, string>} flagged
 * @param {Set<string>} present ids that have a jpg
 * @return {string}
 */
function buildHtml(seed, flagged, present) {
  const cards = seed.map((item) => {
    const isFlagged = flagged.has(item.id);
    const image = present.has(item.id) ?
      `<img src="${escapeHtml(item.id)}.jpg" loading="lazy">` :
      "<div class=\"missing\">no photo</div>";
    const reason = isFlagged ?
      `<br><span class="reason">${escapeHtml(flagged.get(item.id))}</span>` :
      "";
    return `<figure class="${isFlagged ? "flagged" : ""}">${image}` +
      `<figcaption><b>${escapeHtml(item.id)}</b><br>` +
      `${escapeHtml(item.name)}<br>` +
      `<small>${escapeHtml((item.countries ?? []).join(", "))}</small>` +
      `${reason}</figcaption></figure>`;
  }).join("\n");
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>Recovery library (${seed.length})</title>
<style>
body{font-family:system-ui,sans-serif;margin:16px;background:#fafafa}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
figure{margin:0;padding:6px;background:#fff;border:3px solid transparent;border-radius:6px}
figure.flagged{border-color:#d00}
img,.missing{width:100%;aspect-ratio:4/3;object-fit:cover;display:block;background:#ddd}
.missing{display:flex;align-items:center;justify-content:center;color:#888}
figcaption{font-size:13px;margin-top:4px}
.reason{color:#d00;font-weight:600}
</style></head><body>
<h1>Recovery library: ${seed.length} items, ${flagged.size} flagged</h1>
<div class="grid">
${cards}
</div></body></html>
`;
}

/** @param {string[]} argv */
function main(argv) {
  const flags = parseFlags(argv);
  const out = flags.out ? path.resolve(flags.out) : DEFAULT_OUT_DIR;
  fs.mkdirSync(out, {recursive: true});
  const seed = loadSeed();
  const present = new Set(fs.readdirSync(out)
      .filter((name) => name.endsWith(".jpg"))
      .map((name) => name.slice(0, -4)));
  const file = path.join(out, "contact-sheet.html");
  fs.writeFileSync(file, buildHtml(seed, loadFlagged(out), present));
  console.log(`wrote ${file}`);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = {buildHtml, loadFlagged};
