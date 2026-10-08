# MAINTENANCE row 271 mutation battery: WorkerCosts' admin settings reach clients (src/WorkerManager.lua:
# getServerSnapshot's settings, applyClientSnapshot, onSettingsSaved, delete's flag; src/settings/Settings.lua: save's
# notify; src/integrations/WorkerNetworkSyncBridge.lua and src/WCNetworkEvents.lua: the settings on both wires). Rows
# live in tools/test/lua/MAINT-271-settings_reach_clients_test.lua.
#
# TARGETED (Tyson, 2026-09-25 and 2026-09-26, R-25a): the lines this PR changes, Bob's mutant list. Targeted runs only
# (Tyson, 2026-09-30): each mutant runs SELECTED, this PR's bench; the four other benches that load a changed file
# ran once, unmutated, as the PR's selection baseline. This repo's runner has no selection, so the script writes a
# filtered copy of run-tests.mjs beside it for the run and deletes it after. Run ONE mutant per call, in the
# foreground, and check free memory by hand right before each.
#
# The edit is proved to LAND (exact occurrence count) and the restore is proved by a hash. KILLED* means
# killed only by a Lua error or a raised group: a weak kill.
#
# NOT RUN, and why: "a local key overwritten" has no single-edit mutant here: the wire carries no player-local key,
# so the client could only take one if both the producer and SYNCED_SETTINGS gained it (two files); F1 and E1 assert
# the client's debugMode and showNotifications stay its own. Comments.
#
# Usage (from the repo root):
#        py tools/test/mutate_maint271.py <id>        one mutant (prefix match must be unique)
#        py tools/test/mutate_maint271.py --check     every anchor matches its count; runs nothing
#        py tools/test/mutate_maint271.py --baseline  the selected tests, unmutated
#        py tools/test/mutate_maint271.py --list
import hashlib, os, re, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

WM = "src/WorkerManager.lua"
SET = "src/settings/Settings.lua"
BRIDGE = "src/integrations/WorkerNetworkSyncBridge.lua"
EVENTS = "src/WCNetworkEvents.lua"

SELECTED = [
    "MAINT-271-settings_reach_clients_test.lua",
]
FILTER_FROM = 'const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua")).sort();'
FILTER_TO = ('const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua") && '
             'process.env.MUTATE_SELECTED.split(",").includes(f)).sort();')

MUTATIONS = [
 ("M01-ns-wire-unwritten", BRIDGE,
  [("    local settings = snap.settings or {}\n    arr[#arr + 1] = b2i(settings.enabled ~= false)\n",
    "    local settings = {}\n    arr[#arr + 1] = b2i(settings.enabled ~= false)\n", 1)],
  "the NetworkSync aggregate carries defaults, not the server's settings (F1, V1, P1)"),
 ("M02-event-wire-unwritten", EVENTS,
  [("    local settings = snap.settings or {}\n    streamWriteBool(streamId,    settings.enabled ~= false)\n",
    "    local settings = {}\n    streamWriteBool(streamId,    settings.enabled ~= false)\n", 1)],
  "the own WCRosterSyncEvent carries defaults, not the server's settings (E1)"),
 ("M03-not-applied", WM,
  [("    if not isServer and type(st) == \"table\" and self.settings ~= nil then\n", "    if false then\n", 1)],
  "a client stores the snapshot but never applies its settings, as before (F1, V1, P1, D1, H1, E1)"),
 ("M04-applied-through-setters", WM,
  [("            if st[key] ~= nil then self.settings[key] = st[key] end\n",
    "            if st[key] ~= nil then\n"
    "                if key == \"costMode\" then self.settings:setCostMode(st[key])\n"
    "                elseif key == \"wageLevel\" then self.settings:setWageLevel(st[key])\n"
    "                else self.settings[key] = st[key] end\n"
    "            end\n", 1)],
  "the client applies through the setters, logging 'changed to' on every snapshot (L1, E1 (L))"),
 ("M05-applied-on-server", WM,
  [("    if not isServer and type(st) == \"table\" and self.settings ~= nil then\n",
    "    if type(st) == \"table\" and self.settings ~= nil then\n", 1)],
  "a snapshot reaching the server's own apply overwrites the server's settings (G1)"),
 ("M06-no-broadcast-after-save", WM,
  [("    if g_server == nil or g_currentMission == nil or g_currentMission.isMissionStarted ~= true then return end\n    self:_broadcastRosterSync()\n",
    "    if g_server == nil or g_currentMission == nil or g_currentMission.isMissionStarted ~= true then return end\n", 1)],
  "a host's settings write waits for the next roster change, as before (D1, H1, E1)"),
 ("M07-shutdown-sends", WM,
  [("    if self._shuttingDown then return end\n", "", 1)],
  "the shutdown save sends a roster sync (X1)"),
 ("M08-save-does-not-notify", SET,
  [("    if wm ~= nil and wm.settings == self and type(wm.onSettingsSaved) == \"function\" then wm:onSettingsSaved() end\n", "", 1)],
  "the choke point never tells the manager, so no writer reaches the broadcast (D1, H1, E1)"),
]


def sha(b): return hashlib.sha256(b).hexdigest()


def read(rel):
    with open(p(rel), "rb") as f: return f.read()


def anchors(rel, edits):
    data = read(rel)
    crlf = b"\r\n" in data
    out = []
    for old, new, want in edits:
        o = old.encode("utf-8")
        n = new.encode("utf-8")
        if crlf:
            o = o.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            n = n.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        out.append((o, n, want, data.count(o)))
    return data, out


def run_suite():
    here = os.path.join(ROOT, "tools", "test")
    runner = open(os.path.join(here, "run-tests.mjs"), encoding="utf-8").read()
    if runner.count(FILTER_FROM) != 1:
        raise SystemExit("run-tests.mjs changed: the selection anchor is not found once")
    sel = os.path.join(here, "_mutate_selected_runner.mjs")
    with open(sel, "w", encoding="utf-8", newline="\n") as f:
        f.write(runner.replace(FILTER_FROM, FILTER_TO))
    try:
        env = dict(os.environ, MUTATE_SELECTED=",".join(SELECTED))
        r = subprocess.run(["node", "_mutate_selected_runner.mjs"], cwd=here, env=env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    finally:
        os.remove(sel)
    out = r.stdout + r.stderr
    strip = lambda l: (re.sub(r"\x1b\[[0-9;]*m", "", l).strip().encode("ascii", "replace").decode("ascii"))
    lines = [strip(l) for l in out.splitlines()]
    fails = [l for l in lines if l.startswith("FAIL ") or "Lua error" in l or "crashed" in l]
    return r.returncode, fails, out


def main(argv):
    if not argv or argv[0] == "--list":
        for mid, rel, _, why in MUTATIONS: print(f"{mid:34s} {rel}  {why}")
        return 0
    if argv[0] == "--check":
        bad = 0
        for mid, rel, edits, _ in MUTATIONS:
            _, found = anchors(rel, edits)
            for i, (_, _, want, got) in enumerate(found):
                if got != want:
                    bad += 1
                    print(f"ANCHOR {mid} edit {i + 1}: want {want}, found {got}")
        print(f"{len(MUTATIONS)} mutants, {bad} bad anchor(s)")
        return 1 if bad else 0
    if argv[0] == "--baseline":
        rc, fails, out = run_suite()
        tail = [l for l in out.strip().splitlines() if l.strip()]
        print(re.sub(r"\x1b\[[0-9;]*m", "", tail[-1]) if tail else "(no output)")
        return rc
    picked = [m for m in MUTATIONS if m[0].startswith(argv[0])]
    if len(picked) != 1:
        print(f"'{argv[0]}' matches {len(picked)} mutants; name exactly one")
        return 2
    mid, rel, edits, why = picked[0]
    data, found = anchors(rel, edits)
    for i, (_, _, want, got) in enumerate(found):
        if got != want:
            print(f"{mid}: ANCHOR edit {i + 1} want {want}, found {got}; nothing changed")
            return 2
    before = sha(data)
    mutated = data
    for o, n, _, _ in found: mutated = mutated.replace(o, n)
    if mutated == data:
        print(f"{mid}: the edit changed nothing; not run")
        return 2
    try:
        with open(p(rel), "wb") as f: f.write(mutated)
        rc, fails, _ = run_suite()
    finally:
        with open(p(rel), "wb") as f: f.write(data)
    after = sha(read(rel))
    if after != before:
        print(f"{mid}: RESTORE FAILED ({before[:12]} -> {after[:12]})")
        return 3
    assertion = [f for f in fails if "Lua error" not in f and "crashed" not in f and not f.startswith("FAIL -")]
    verdict = "SURVIVED" if rc == 0 else ("KILLED" if assertion else "KILLED*")
    print(f"{mid}: {verdict}  ({why}); restored {before[:12]}")
    shown = assertion + [f for f in fails if f not in assertion]
    for f in shown[:12]: print("    " + f[:220])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
