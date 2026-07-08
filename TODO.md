# TODO: FS25_WorkerCosts

> Ecosystem role: **Labor** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [ ] Fast-track F1: add the Legendary (Level 4) tier with the locked values (XP 400, wage factor 0.85, hire 120h, severance factor 2.5). Decided, no latitude.
- [ ] Point 7: gate the wage-charge chain to the server (`getIsServer()` on workerSystem:update + hireHall:update at the call site).
- [ ] Point 5: wire ProStaff modifiers into calculateLaborCost + fatigue recovery.
- [ ] Decide the billing model (real-time vs flat daily on onDayChange) before companions wire in.

## Bugs
- [!] CRITICAL (MP): the wage-charge chain (getActiveWorkers -> processWorkerPayments -> chargeWage -> addMoney) runs ungated on every peer; WorkerSystem.lua has zero getIsServer references. Balances can desync. (Point 7 / review F15-F19 class.)
- [!] Design flag: real-time billing (30 real-min interval) makes wages depend on game speed, breaking coherence with the onDayChange cost systems.
- [ ] G2: the addMoney fallback heuristic suppresses any negative addMoney <= 500 during an AI job when MoneyType.AI is unavailable; can eat a legit small fee. Tighten or log.

## Features / enhancements
- [ ] Legendary tier (F1) + the 6-function companion read API.

## Cross-mod integration
- [ ] StateLedger: workerData + hireHallCore modules. NetworkSync: WCWorkerCommandEvent / WCRosterSyncEvent / WCRequestRosterSyncEvent. MasterHUD: roster panel. SettingsHub: remove ESC WorkerSettingsUI.
- [ ] Reads ProStaff `proStaffManager`. Read by DairyCore, TaxMod, WorkplaceTriggers.
- [x] KEEP the addMoney MoneyType.AI suppression hook (permanent; must survive any restructuring).

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [!] Billing-model decision (waits on: TysonK/Arissani; blocks ProStaff and DairyCore wiring).
