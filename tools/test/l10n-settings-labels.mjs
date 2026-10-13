// l10n-settings-labels.mjs: every settings row the code builds has its label and tooltip text.
//
// UIHelper.createBinaryOption and createMultiOption (src/utils/UIHelper.lua:40, :119) label a
// row with getTextSafe(textId .. "_short") (:80, :163) and set its tooltip from
// getTextSafe(textId .. "_long"). A missing _short key draws the raw fallback on the settings
// screen (a player's report, 2026-09-25: the Cost Mode and Wage rows). This reads every
// UIHelper.create*Option call in src/ (its third argument is the textId) and requires both
// keys to be declared, with an <en> child, in modDesc.xml's inline <l10n> block, where
// WorkerCosts keeps its strings (see l10n-once.mjs). With `--all-langs KEY,...` it also
// requires each named key in every language the translation files exist for.
//
// Exit 0 when every row has both texts; exit 1 naming each missing key.
// Usage: node tools/test/l10n-settings-labels.mjs [--all-langs key1,key2]
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const allIdx = process.argv.indexOf("--all-langs");
const allLangKeys = allIdx > 0 ? process.argv[allIdx + 1].split(",") : [];

function luaFiles(dir) {
  const out = [];
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) out.push(...luaFiles(p));
    else if (n.endsWith(".lua")) out.push(p);
  }
  return out;
}

const modDesc = readFileSync(join(root, "modDesc.xml"), "utf8");
const block = modDesc.match(/<l10n[^>]*>([\s\S]*?)<\/l10n>/);
const inline = new Map();
for (const m of (block ? block[1] : "").matchAll(/<text\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/text>/g)) {
  inline.set(m[1], new Set([...m[2].matchAll(/<([a-z]{2})>/g)].map((x) => x[1])));
}
const langs = readdirSync(join(root, "translations"))
  .map((n) => n.match(/^translation_([a-z]{2})\.xml$/)).filter(Boolean).map((m) => m[1]).sort();

const rows = [];
for (const f of luaFiles(join(root, "src"))) {
  const src = readFileSync(f, "utf8").replace(/\s+/g, " ");
  for (const m of src.matchAll(/UIHelper\.create(Binary|Multi)Option\(\s*[^,()]+,\s*"([^"]+)",\s*"([^"]+)"/g)) {
    rows.push({ file: f.slice(root.length + 1).replace(/\\/g, "/"), kind: m[1], id: m[2], textId: m[3] });
  }
}

const failures = [];
for (const r of rows) {
  for (const suffix of ["_short", "_long"]) {
    const key = r.textId + suffix;
    const have = inline.get(key);
    if (!have || !have.has("en")) failures.push(`${r.file}: ${r.kind} row "${r.id}" needs ${key} (inline, with <en>)`);
  }
}
for (const key of allLangKeys) {
  const have = inline.get(key) || new Set();
  const missing = langs.filter((l) => !have.has(l));
  if (missing.length) failures.push(`${key}: no text for ${missing.join(", ")}`);
}

if (rows.length === 0) failures.push("no UIHelper.create*Option call found in src/: the bar reads nothing");
if (failures.length) {
  for (const f of failures) console.log("FAIL " + f);
  console.log(`l10n-settings-labels: ${failures.length} failure(s) over ${rows.length} rows`);
  process.exit(1);
}
console.log(`l10n-settings-labels: PASS - ${rows.length} rows, each with its _short label and _long tooltip inline` +
  (allLangKeys.length ? `; ${allLangKeys.join(", ")} in all ${langs.length} languages` : ""));
