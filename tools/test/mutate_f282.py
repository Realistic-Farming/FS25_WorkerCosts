# WorkerCosts RSF-F282 mutation battery: the backwards-clock discriminator in
# src/WorkerSystem.lua consumeInGameMs. Rows live in RSF-F282-backwards_clock_test.lua.
#
# SEPARATE FILE ON PURPOSE: each item's battery belongs to its own work.
#
# KILLED* means killed only by a Lua error: a weak kill, treated as a failure.
#
# NOT RUN, and why:
#   - the daily settlement's day-change branch: a backward monotonic day is unreachable
#     for the server's WorkerSystem (the tick only increments it, the console setter holds
#     it on the brief's reading of its empty lower-time branch, Environment.lua:579-581,
#     and every mission load re-baselines the markers, WorkerSystem:initialize),
#     so no bar can reach a rewind there and the branch is left as it was.
#
# Anchors are written with "\n"; in a CRLF file they are matched as "\r\n".
#
# RUN IT ALONE, through the test lock. A battery edits production files in place.
#
# Usage: py tools/test/mutate_f282.py [id-prefix ...]
import hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

WS = "src/WorkerSystem.lua"

MUTATIONS = [
 ("F1-discriminator-removed", WS,
  [("        if env.currentMonotonicDay ~= nil then\n", "        if false then\n", 1)],
  "a same-day rewind is read as a midnight wrap and bills most of a day"),
 ("F2-rewind-bills-the-negative-span", WS,
  [("            Logging.info(\"[Worker Costs] Clock moved backwards by %d in-game ms (day %d); nothing billed, clock re-baselined\", -delta, monotonicDay)\n            return 0\n",
    "            Logging.info(\"[Worker Costs] Clock moved backwards by %d in-game ms (day %d); nothing billed, clock re-baselined\", -delta, monotonicDay)\n            return delta\n", 1)],
  "a rewind bills a negative span, un-earning worked hours"),
 ("F3-rewind-not-logged", WS,
  [("            Logging.info(\"[Worker Costs] Clock moved backwards by %d in-game ms (day %d); nothing billed, clock re-baselined\", -delta, monotonicDay)\n", "", 1)],
  "a developer who rewinds the clock sees nothing"),
 ("F4-discriminator-inverted", WS,
  [("        if env.currentMonotonicDay ~= nil then\n", "        if env.currentMonotonicDay == nil then\n", 1)],
  "with the counter the wrap arithmetic runs, without it the rewind refusal runs"),
 ("F5-baseline-not-moved-on-rewind", WS,
  [("    local lastMs = self.lastAbsoluteGameTimeMs\n    self.lastAbsoluteGameTimeMs = nowMs\n",
    "    local lastMs = self.lastAbsoluteGameTimeMs\n    if nowMs >= (lastMs or 0) then self.lastAbsoluteGameTimeMs = nowMs end\n", 1)],
  "the stale baseline stays, so the next forward hour bills the span back to the position the clock left"),
 ("W103-rewind-said-twice", "src/WorkerSystem.lua",
  [("            -- Logging.info only (MAINTENANCE row 103: it used to be said twice).\n            Logging.info",
    "            -- Logging.info only (MAINTENANCE row 103: it used to be said twice).\n            self:log(\"Clock moved backwards by %d in-game ms on day %d; nothing billed, clock re-baselined\", -delta, monotonicDay)\n            Logging.info", 1)],
  "the rewind is said twice with debug mode on (the mod's own debug line restored)"),
]


def sha(b): return hashlib.sha256(b).hexdigest()


def run_suite():
    r = subprocess.run(["node", "run-tests.mjs"], cwd=os.path.join(ROOT, "tools", "test"),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = r.stdout + r.stderr
    strip = lambda l: (re.sub(r"\x1b\[[0-9;]*m", "", l).strip()
                       .encode("ascii", "replace").decode("ascii"))
    fails = [strip(l) for l in out.splitlines() if "FAIL" in l and "assertions passed" not in l]
    crashes = [strip(l) for l in out.splitlines() if "Lua error while loading/running" in l]
    return r.returncode, fails, crashes


only = sys.argv[1:]
rc, fails, crashes = run_suite()
if rc != 0:
    print("BASELINE IS NOT GREEN; fix that before trusting any mutation result.")
    for l in fails[:10]:
        print("   " + l)
    sys.exit(2)
print("baseline green")

killed, crashkills, survived, badedit = [], [], [], []

for mid, rel, edits, why in MUTATIONS:
    if only and not any(mid.startswith(o) for o in only):
        continue
    path = p(rel)
    with open(path, "rb") as f:
        original = f.read()
    crlf = b"\r\n" in original
    enc = lambda s: (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")

    ok, mutated = True, original
    for old, new, want in edits:
        ob, nb = enc(old), enc(new)
        n = mutated.count(ob)
        if n != want:
            badedit.append((mid, "anchor matched %dx, expected %d" % (n, want)))
            print("  !! %s: ANCHOR MISMATCH (%d != %d), mutation NOT applied" % (mid, n, want))
            ok = False
            break
        mutated = mutated.replace(ob, nb, want)
    if not ok:
        continue

    with open(path, "wb") as f:
        f.write(mutated)
    with open(path, "rb") as f:
        landed = f.read()
    if landed == original or landed != mutated:
        with open(path, "wb") as f:
            f.write(original)
        badedit.append((mid, "edit did not land"))
        print("  !! %s: EDIT DID NOT LAND" % mid)
        continue

    try:
        rc, fails, crashes = run_suite()
    finally:
        with open(path, "wb") as f:
            f.write(original)
    with open(path, "rb") as f:
        if sha(f.read()) != sha(original):
            print("  !! %s: RESTORE FAILED, stopping" % mid)
            sys.exit(3)

    named = [l for l in fails if l.startswith("FAIL ")]
    if rc != 0:
        killed.append(mid)
        tag = "KILLED  "
        if crashes and not named:
            crashkills.append(mid)
            tag = "KILLED* "
    else:
        survived.append((mid, why))
        tag = "SURVIVED"
    print("  %s %s  [%s]" % (tag, mid, rel))
    print("        (%s)" % why)
    for l in named[:4]:
        print("        " + l[:170])
    for l in crashes[:2]:
        print("        CRASH " + l[:170])

print("\n==== MUTATION RESULT ====")
print("killed   %d (of which %d only by a Lua error, marked KILLED*)" % (len(killed), len(crashkills)))
print("survived %d" % len(survived))
print("bad edit %d" % len(badedit))
for mid, why in survived:
    print("--- SURVIVED %s: %s" % (mid, why))
for mid, msg in badedit:
    print("--- BAD EDIT %s: %s" % (mid, msg))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit or crashkills) else 0)
