// l10n-once.mjs: every l10n key of this mod is declared in ONE place.
//
// The engine loads modDesc.xml's inline <l10n> block first (mods.lua:772) and the
// translation files after (:802, :813); a key present in both draws "Duplicate l10n
// entry ... Ignoring this definition" on every load and the file copy is silently
// ignored, so an edit to it does nothing (MAINTENANCE row 65). WorkerCosts keeps its
// strings inline in modDesc.xml; the translation files carry only what is not inline.
//
// The translation files are the ones the engine reads: modDesc.l10n#filenamePrefix
// (mods.lua:783-786) plus "_<lang>.xml"; defaultLanguage is never read by the engine.
// An inline <text> with no language child is skipped by the engine (:774-777), so its
// file copy would be live and it is not counted as inline here.
//
// Exit 0 when no key is declared both inline and in a translation file; exit 1 with the
// offending keys otherwise. Usage: node tools/test/l10n-once.mjs [repo root]
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const root = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const modDesc = readFileSync(join(root, "modDesc.xml"), "utf8");
const l10nBlock = modDesc.match(/<l10n([^>]*)>([\s\S]*?)<\/l10n>/);
const inline = new Set();
let prefix = "translations/translation";
if (l10nBlock) {
  const attr = l10nBlock[1].match(/filenamePrefix="([^"]+)"/);
  if (attr) prefix = attr[1];
  for (const m of l10nBlock[2].matchAll(/<text\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/text>/g)) {
    if (/<[a-z]{2}(?:[_-][a-zA-Z]+)?>/.test(m[2])) inline.add(m[1]);
  }
}
const dir = join(root, dirname(prefix));
const stem = basename(prefix);
const overlaps = [];
let fileKeys = 0;
for (const f of readdirSync(dir).filter((n) => n.startsWith(stem + "_") && n.endsWith(".xml")).sort()) {
  const xml = readFileSync(join(dir, f), "utf8");
  const keys = [...xml.matchAll(/<text\s+name="([^"]+)"/g)].map((m) => m[1])
    .concat([...xml.matchAll(/<e\s+k="([^"]+)"/g)].map((m) => m[1]));
  fileKeys += keys.length;
  for (const k of keys) if (inline.has(k)) overlaps.push(`${f}: ${k}`);
}
if (overlaps.length > 0) {
  console.error(`  x l10n keys declared both inline in modDesc.xml and in a translation file (${overlaps.length}):`);
  for (const o of overlaps) console.error("    " + o);
  process.exit(1);
}
console.log(`  ✓ l10n keys declared once - ${inline.size} inline, ${fileKeys} in translation files, 0 overlaps`);
