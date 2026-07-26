# TODO: FS25_WorkerCosts

> Ecosystem role: **Labor** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [x] Fast-track F1: Legendary (Level 4) tier with locked values (XP 400, wage factor 0.85, hire 120h, severance factor 2.5). DONE (d20da2f), shipped in v2.2.2.2.
- [x] Point 7: wage-charge chain gated to the server. DONE (8c70f45), shipped in v2.2.2.2.
- [!] Point 5: wire ProStaff modifiers into calculateLaborCost + fatigue recovery. Blocked on ProStaff (brief pulled, under re-review).
- [x] Billing model decided + built: per-in-game-day billing (middle path), replacing the real-time interval. DONE (0c808d1), shipped in v2.2.2.2.

## Bugs
- [x] Monthly-salary double-charge (100d3c6): monthly-salary billing mode no longer charges wages twice. This is the ledger's WorkerCosts monthly double-charge gremlin (WorkerSystem.lua), closed.
- [x] CRITICAL (MP): the wage-charge chain ran ungated on every peer; now server-gated. FIXED (8c70f45), shipped in v2.2.2.2. (Point 7 / F15-F19 class.)
- [x] Design flag resolved: real-time billing replaced by per-in-game-day billing, coherent with the onDayChange cost systems. DONE (0c808d1).
- [x] G2: the addMoney fallback heuristic tightened. DONE (8c70f45).
- [x] Legendary surcharge-DISPLAY fix: the roster estimate no longer surcharges Legendary workers (matches the authoritative charge). DONE (b84728f), shipped in v2.2.2.2.
- [x] WC-001 / WC-002 / WC-003: additional WorkerCosts bugs fixed in 2026-07-26 bug sweep, merged to main.

## Features / enhancements
- [~] Legendary tier DONE (d20da2f). The 6-function companion read API is partial: getWorkersForFarm shipped (90ce2e1); the rest pending the DairyCore/ProStaff builds.

## Cross-mod integration
- [x] Bedrock bridges built, delegate-when-present: StateLedger workerData + hireHallCore (4328920), MasterHUD roster panel (4b10bd5), NetworkSync v2 first dual-consumer (c179141), SettingsHub (ff35ed0). Shipped in v2.2.2.2. (Removing the ESC WorkerSettingsUI is still open.)
- [ ] Reads ProStaff `proStaffManager` (pending ProStaff). Read by DairyCore, TaxMod, WorkplaceTriggers.
- [x] KEEP the addMoney MoneyType.AI suppression hook (permanent; must survive any restructuring).

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [x] Billing-model decision RESOLVED: per-in-game-day (middle path), built (0c808d1).
- [!] ProStaff modifier wiring (Point 5) waits on the ProStaff build (brief pulled, under re-review).
