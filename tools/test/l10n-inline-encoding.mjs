// l10n-inline-encoding.mjs: no inline text in modDesc.xml is UTF-8 encoded twice (MAINTENANCE row 143).
//
// WorkerCosts keeps its strings inline in modDesc.xml (see l10n-once.mjs). 134 of them had been
// saved as the UTF-8 bytes of their own UTF-8 bytes read as Windows-1252, twice, so Polish
// "Miesięczne" was stored as "MiesiÃ„â„¢czne" and every accented or non-Latin letter read as
// garbage in game. A value is flagged when reading its characters back as Windows-1252 bytes
// gives a DIFFERENT valid UTF-8 string: that is exactly the mis-encoding, and correct text
// (any letter outside Windows-1252, or a Latin-1 letter standing alone) never decodes so.
//
// Exit 0 when no inline value decodes that way; exit 1 naming each. Usage: node tools/test/l10n-inline-encoding.mjs
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const modDesc = readFileSync(join(root, "modDesc.xml"), "utf8");
const block = modDesc.match(/<l10n[^>]*>([\s\S]*?)<\/l10n>/);

// Windows-1252's 0x80-0x9F block; every other byte maps to the same code point (Latin-1).
const CP1252 = { 0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88,
  0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94,
  0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F };
const decoder = new TextDecoder("utf-8", { fatal: true });
function undoOnce(s) {
  const bytes = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (CP1252[cp] !== undefined) bytes.push(CP1252[cp]);
    else if (cp < 256) bytes.push(cp);
    else return null;
  }
  try { return decoder.decode(new Uint8Array(bytes)); } catch { return null; }
}

const failures = [];
let values = 0;
for (const t of (block ? block[1] : "").matchAll(/<text\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/text>/g)) {
  for (const v of t[2].matchAll(/<([a-z]{2})>([\s\S]*?)<\/\1>/g)) {
    values++;
    const u = undoOnce(v[2]);
    if (u !== null && u !== v[2]) failures.push(`${t[1]} <${v[1]}>: "${v[2].slice(0, 30)}" decodes to "${u.slice(0, 30)}": UTF-8 encoded twice`);
  }
}
if (!block) failures.push("modDesc.xml has no inline <l10n> block: the bar reads nothing");
if (failures.length) {
  for (const f of failures.slice(0, 40)) console.log("FAIL " + f);
  console.log(`l10n-inline-encoding: ${failures.length} failure(s) over ${values} inline values`);
  process.exit(1);
}
console.log(`l10n-inline-encoding: PASS - ${values} inline values, none UTF-8 encoded twice`);
