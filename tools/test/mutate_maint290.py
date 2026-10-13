# MAINTENANCE row 290 mutation battery: a client admin's WorkerCosts settings edit reaches the server
# (src/WorkerManager.lua: onSettingsSaved's client branch, _adminEditsSinceSnapshot, SETTING_CHECKS,
# applySettingsFromNetwork; src/integrations/WorkerNetworkSyncBridge.lua: the SetSettings action and sendSettings;
# src/WCNetworkEvents.lua: WCSettingsChangeEvent and WCNetwork_SendSettings; src/settings/Settings.lua:
# canEditAdminSettings and resetForUser; the admin lock in src/gui/WCWageSettingsFrame.lua,
# src/settings/WorkerSettingsUI.lua and src/gui/WcRfPdaGuest.lua). Rows live in
# tools/test/lua/MAINT-290-client_admin_edits_test.lua.
#
# TARGETED (Tyson, 2026-09-25 and 2026-09-26, R-25a): the lines this PR changes, Bob's mutant list plus his reset
# amendment. Targeted runs only (Tyson, 2026-09-30): each mutant runs SELECTED, this PR's bench; the five other
# benches that load a changed file ran once, unmutated, as the PR's selection baseline. This repo's runner has no
# selection, so the script writes a filtered copy of run-tests.mjs beside it for the run and deletes it after. Run
# ONE mutant per call, in the foreground, and check free memory by hand right before each.
#
# The edit is proved to LAND (exact occurrence count) and the restore is proved by a hash. KILLED* means
# killed only by a Lua error or a raised group: a weak kill.
#
# Usage (from the repo root):
#        py tools/test/mutate_maint290.py <id>        one mutant (prefix match must be unique)
#        py tools/test/mutate_maint290.py --check     every anchor matches its count; runs nothing
#        py tools/test/mutate_maint290.py --baseline  the selected tests, unmutated
#        py tools/test/mutate_maint290.py --list
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
FRAME = "src/gui/WCWageSettingsFrame.lua"
UI = "src/settings/WorkerSettingsUI.lua"
PDA = "src/gui/WcRfPdaGuest.lua"
GUI = "src/settings/WorkerSettingsGUI.lua"

SELECTED = [
    "MAINT-290-client_admin_edits_test.lua",
]
FILTER_FROM = 'const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua")).sort();'
FILTER_TO = ('const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua") && '
             'process.env.MUTATE_SELECTED.split(",").includes(f)).sort();')

MUTATIONS = [
 ("M01-ns-gate-open", BRIDGE,
  [("    ns:registerAction(A.SET_SETTINGS, { adminOnly = true, onAction", "    ns:registerAction(A.SET_SETTINGS, { adminOnly = false, onAction", 1)],
  "NetworkSync lets a client that is not master change the admin settings (E0, R1)"),
 ("M02-event-gate-open", EVENTS,
  [("    if user == nil or not user:getIsMasterUser() then\n", "    if false then\n", 1)],
  "the own event applies a client that is not master (ER2)"),
 ("M03-sends-unchanged-keys", WM,
  [("        if value ~= nil and value ~= base[key] then\n", "        if value ~= nil then\n", 1)],
  "every save sends all five admin keys, so a Notifications edit sends (B1, L0, S0)"),
 ("M04-no-baseline-guard", WM,
  [("    local base = type(snap) == \"table\" and snap.settings or nil\n    if type(base) ~= \"table\" or self.settings == nil then return nil end\n",
    "    local base = type(snap) == \"table\" and snap.settings or {}\n    if self.settings == nil then return nil end\n", 1)],
  "a save before the first snapshot pushes the client's file values at the server (N0)"),
 ("M05-shutdown-sends", WM,
  [("    if self._shuttingDown then return end\n", "", 1)],
  "the quit save sends the client's unsent admin edit (Q0)"),
 ("M06-validation-open", WM,
  [("    customRate           = function(v) return type(v) == \"number\" and v >= 0 and v <= 1000 end,\n",
    "    customRate           = function(v) return type(v) == \"number\" and v >= 0 end,\n", 1)],
  "the server takes a custom rate of 5000 (V0, EV0)"),
 ("M07-apply-without-save", WM,
  [("    if applied > 0 then\n        s:save()\n    end\n", "", 1)],
  "the server applies but never saves, so no broadcast and the third machine never converges (B1, S0, EB1)"),
 ("M08-no-refusal-reply", EVENTS,
  [("    if not ok then\n        connection:sendEvent(WCRosterSyncEvent.new(wm:getServerSnapshot()))\n    end\n", "", 1)],
  "a refused request through the own event is not answered, so the client keeps its edit (ER2, EV0, EM0)"),
 ("M09-lock-helper-open", SET,
  [("    return g_server ~= nil or (g_currentMission ~= nil and g_currentMission.isMasterUser == true)\n", "    return true\n", 1)],
  "every machine may edit the admin settings: nothing locks, B's reset and PDA apply write them (U1, U2, U3, P0, S1)"),
 ("M10-tab-unlocked", FRAME,
  [("    self:applyAdminLock()\n    self:refreshRatePreview()\n", "    self:refreshRatePreview()\n", 1)],
  "the wage settings tab never locks (U1)"),
 ("M11-rows-unlocked", UI,
  [("    end\n\n    self:applyAdminLock()\nend\n", "    end\nend\n", 1)],
  "the game's settings screen rows never lock at a later open (U2)"),
 ("M12-pda-unlocked", PDA,
  [("        if opt ~= nil and type(opt.setDisabled) == \"function\" then opt:setDisabled(locked) end\n", "", 1)],
  "the PDA page never locks (U3)"),
 ("M13-reset-all-keys", SET,
  [("    if Settings.canEditAdminSettings() then\n        self:resetToDefaults()\n", "    if true then\n        self:resetToDefaults()\n", 1)],
  "a reset on a client that is not master resets and sends the admin keys (S1)"),
 ("M14-guard-in-shared-reset", SET,
  [("function Settings:resetToDefaults(saveImmediately)\n    saveImmediately = saveImmediately ~= false\n",
    "function Settings:resetToDefaults(saveImmediately)\n    saveImmediately = saveImmediately ~= false\n"
    "    if not Settings.canEditAdminSettings() then\n"
    "        self.showNotifications = true\n        self.debugMode = false\n"
    "        if saveImmediately then self:save() end\n        return\n    end\n", 1)],
  "Bob's: the guard inside the shared reset, so a pure client's Settings.new leaves the admin keys nil (K0)"),
 ("M15-pda-writes-locked-keys", PDA,
  [("    if canAdmin and optCostMode and optCostMode.getState and settings.setCostMode then\n",
    "    if optCostMode and optCostMode.getState and settings.setCostMode then\n", 1)],
  "a locked client's PDA apply writes a stale cost mode over the server's (P0)"),
 ("M16-rows-not-refreshed-on-reopen", UI,
  [("        self:refreshUI()\n        return\n    end\n", "        return\n    end\n", 1)],
  "a later open of the game's settings screen neither refreshes nor locks the rows (U2)"),
 ("M17-client-save-silent", WM,
  [("    elseif g_client ~= nil then\n        self:_sendAdminEditsToServer()\n", "    elseif false then\n        self:_sendAdminEditsToServer()\n", 1)],
  "a client's save sends nothing, as before: an admin's edit never reaches the server (B1, S0, EB1)"),
 ("M18-tab-reset-all-keys", FRAME,
  [("        g_WorkerManager.settings:resetForUser()   -- [MAINTENANCE row 290] the player's own keys only, where locked\n",
    "        g_WorkerManager.settings:resetToDefaults()\n", 1)],
  "the wage settings tab's reset back to the full reset (S1)"),
 ("M19-pda-reset-all-keys", PDA,
  [("    mgr.settings:resetForUser()   -- [MAINTENANCE row 290] the player's own keys only, where locked\n",
    "    mgr.settings:resetToDefaults()\n", 1)],
  "the PDA page's reset back to the full reset (S2)"),
 ("M20-rows-reset-all-keys", UI,
  [("                    g_WorkerManager.settings:resetForUser()   -- [MAINTENANCE row 290]\n",
    "                    g_WorkerManager.settings:resetToDefaults()\n", 1)],
  "the settings screen's reset button back to the full reset (S2)"),
 ("M21-console-reset-all-keys", GUI,
  [("        g_WorkerManager.settings:resetForUser()   -- [MAINTENANCE row 290] the player's own keys only, where locked\n",
    "        g_WorkerManager.settings:resetToDefaults()\n", 1)],
  "the console reset back to the full reset (S2)"),
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
