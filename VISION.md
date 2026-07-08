# Vision: FS25_WorkerCosts

> Ecosystem role: **Labor** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit (Point 1-7, ecosystem-map, notes).
> Last updated: 2026-07-08

## 1. One-line purpose
AI helpers and hired workers cost real money over time: wages by skill tier, fatigue, night and weather premiums, hire cost and severance, so staffing a farm is a budget decision.

## 2. Problem it solves
FS25 AI workers are nearly free once hired, so there is no labour economy. WorkerCosts turns labour into a recurring cost with tiers, fatigue and severance, making crew size and usage something you plan and pay for.

## 3. Design pillars
- **Server-authoritative wages.** The wage-charge chain must run on the server only. Today `workerSystem:update` and `hireHall:update` run ungated on every peer (Point 7), which is a multiplayer-money risk to fix.
- **The addMoney hook is permanent.** WorkerCosts hooks `g_currentMission.addMoney` to suppress the base-game MoneyType.AI wage deduction (the `_isProcessingPayment` flag lets its own charges through). This prevents double-charging and must never be removed during migration.
- **Bill on the farm calendar, not the wall clock.** The current real-time billing (30 real-minute interval) makes wages depend on game speed and breaks ecosystem coherence; the intended model is a flat daily rate on onDayChange (design decision, flagged).
- **ProStaff-aware, neutral when absent.** Wage and fatigue modifiers read from ProStaff when present and default to 1.0 when not.

## 4. Role in the ecosystem
- Public handle on `g_currentMission.workerCostsManager` (all lowercase). Internal `g_WorkerManager` is getfenv-scoped, not cross-mod.
- Reads from (consumes): ProStaff (`g_currentMission.proStaffManager`): getLevel (Legendary gate), getWageModifier, getFatigueRecoveryBonus, getFatigueMitigation. HireHallProStaff.lua is an INTERNAL facade, not a ProStaff ecosystem bridge.
- Read by (consumers): DairyCore (worker tier for legendaryWorkerScan), TaxMod (monthly wage totals), WorkplaceTriggers (reads WorkerCosts, not the reverse), FarmTablet WorkerCostsApp/PersonnelApp, via 6 companion read functions.
- Core-API registration status (specced in Point 1-7, not yet wired):
  - StateLedger (save/load): planned, replacing workerData.xml + hireHallCore.xml.
  - NetworkSync (MP state): planned, replacing 3 event classes (WCWorkerCommandEvent, WCRosterSyncEvent, WCRequestRosterSyncEvent).
  - MasterHUD (overlays): planned, replacing the FSBaseMission.draw hook + addModEventListener + roster GUI.
  - SettingsHub (admin settings): planned, replacing the ESC-menu WorkerSettingsUI injection.

## 5. Explicit non-goals
- Not a ProStaff bridge internally: HireHallProStaff.lua is a facade, not the ecosystem ProStaff integration.
- Does not remove the addMoney MoneyType.AI suppression hook (permanent, architectural).
- Not a wage payer for off-farm jobs (that data flows in from WorkplaceTriggers).

## 6. Success criteria
- Wages are predictable and budget-able per in-game day, consistent with the other cost systems (IncomeMod, TaxMod on onDayChange).
- Wage charging happens on the server only; farm balances stay consistent in multiplayer.
- ProStaff modifiers apply when present and are neutral when absent; the four worker tiers (including Legendary) behave to spec.

## 7. Open questions for the audit
- Billing model: move from real-time (30 real minutes) to a flat daily rate on onDayChange? This must be decided before ProStaff and DairyCore wire in (changing it later is painful).
- The addMoney fallback heuristic (suppresses any negative addMoney <= 500 during an active AI job when MoneyType.AI is unavailable) can silently eat a legitimate small fee. Tighten or log?
