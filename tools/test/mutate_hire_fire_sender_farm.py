# MAINTENANCE row 117 mutation battery: hire and fire charge the sender's farm on both routes
# (src/integrations/WorkerNetworkSyncBridge.lua: the NS handlers resolve the farm from the user,
# sendCommand stands down on a server; src/WCNetworkEvents.lua: the own event resolves the farm
# from the connection). Rows live in MAINT-117-hire_fire_sender_farm_test.lua; the other bars run
# with it.
#
# Each mutation restores one piece of the defect or bends one clause and must be KILLED by a
# named row. For each: assert the edit LANDED (exact occurrence count), run the suite, record
# KILLED/SURVIVED with the named rows, restore byte-for-byte and PROVE the restore with a hash.
# "DID NOT APPLY" never counts as a kill. KILLED* means killed only by a Lua error: a weak kill,
# a failure.
#
# Not run, and why:
# - the transport itself (the fixture copies of NetworkSync): not this repo's code.
# - the writers (_doHire, _doFire, chargeHireCost, chargeSeverance): unchanged by this PR; the
#   rows drive them for the charge's farm, which is the subject.
# - worker ownership (any client may fire or assign any worker): a Design question, excluded by
#   the row; rows N7 and E6 pin only the charge.
#
# Anchors are written with "\n"; in a CRLF file they are matched as "\r\n".
#
# Usage (from the repo root): py tools/test/mutate_hire_fire_sender_farm.py [id-prefix ...]
import hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

BR = "src/integrations/WorkerNetworkSyncBridge.lua"
EV = "src/WCNetworkEvents.lua"

MUTATIONS = [
 # ── the NetworkSync route ───────────────────────────────────────────────────
 ("B1-hire-charges-the-wire-farm", BR,
  [("        local farmId = chargedFarm(userId, args and args[2], WCCommand.HIRE)\n",
    "        local farmId = (args and args[2]) or 0\n        if farmId == 0 then farmId = nil end\n", 1)],
  "the NS hire charges whatever farm the client named"),
 ("B2-fire-charges-the-wire-farm", BR,
  [("        local farmId = chargedFarm(userId, args and args[2], WCCommand.FIRE)\n",
    "        local farmId = (args and args[2]) or 0\n        if farmId == 0 then farmId = nil end\n", 1)],
  "the NS fire charges whatever farm the client named"),
 ("B3-no-user-charges-the-host", BR,
  [("        if userId == nil then\n            Logging.warning(\"[Worker Costs] Rejected NS action (action=%d) - no user for the sender\", action)\n            return nil\n        end\n",
    "        if userId == nil then\n            return (g_currentMission and g_currentMission:getFarmId()) or nil\n        end\n", 1)],
  "a connection with no user is charged to the host's farm"),
 ("B4-spectator-farm-zero-admitted", BR,
  [("        if type(farmId) ~= \"number\" or farmId <= 0 then\n            Logging.warning(\"[Worker Costs] Rejected NS action (action=%d) - the sender is in no farm\", action)\n            return nil\n        end\n",
    "        if type(farmId) ~= \"number\" then\n            return nil\n        end\n", 1)],
  "a spectator's farm 0 reaches the charge"),
 ("B5-mismatch-not-refused", BR,
  [("        if wireFarmId ~= nil and wireFarmId ~= 0 and wireFarmId ~= farmId then\n            Logging.warning(\"[Worker Costs] Rejected NS action (action=%d) - names farm %s but is farm %d\", action, tostring(wireFarmId), farmId)\n            return nil\n        end\n",
    "", 1)],
  "a client naming another farm is charged to its own farm instead of refused"),
 ("B6-host-routed-through-the-core", BR,
  [("    if g_currentMission ~= nil and g_currentMission:getIsServer() then return false end\n", "", 1)],
  "the host's own door goes through NetworkSync's in-memory apply with no user and is refused"),
 # ── the own-event route ─────────────────────────────────────────────────────
 ("E1-event-charges-the-wire-farm", EV,
  [("        farmId = senderFarm\n", "        farmId = self.farmId\n", 1)],
  "the own event charges whatever farm the client named"),
 ("E2-event-no-record-not-refused", EV,
  [("        if type(senderFarm) ~= \"number\" or senderFarm <= 0 then\n            Logging.warning(\"[Worker Costs] Rejected command (action=%d) - the sender has no farm\", self.action)\n            return\n        end\n",
    "        if senderFarm == nil then senderFarm = self.farmId end\n", 1)],
  "a connection with no player record, or a spectator, is charged the wire farm"),
 ("E3-event-mismatch-not-refused", EV,
  [("        if self.farmId ~= nil and self.farmId ~= 0 and self.farmId ~= senderFarm then\n            Logging.warning(\"[Worker Costs] Rejected command (action=%d) - names farm %s but is farm %d\", self.action, tostring(self.farmId), senderFarm)\n            return\n        end\n",
    "", 1)],
  "a client naming another farm is charged to its own farm instead of refused"),
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
for mid, why in survived:
    print("   SURVIVED %s: %s" % (mid, why))
print("bad edit %d" % len(badedit))
for mid, why in badedit:
    print("   BAD EDIT %s: %s" % (mid, why))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit or crashkills) else 0)
