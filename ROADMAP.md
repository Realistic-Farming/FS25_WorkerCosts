# Roadmap: FS25_WorkerCosts

> Ecosystem role: **Labor** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline.
> Forward-looking only. Shipped history lives in CHANGELOG.md and the releases.

## How to use this file
- Populate the milestones below from the audit baseline once it lands.
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: v2.2.2.0
- Audit reference: ecosystem-dev-tracking Point 1-7 (FS25_WorkerCosts, 2026-06-30 / 2026-07-01)
- Baseline date: 2026-07-01

## Near-term (next release cycle)
- [x] Server-authoritative wage path (Point 7): wage-charge chain gated with `getIsServer()`. DONE (8c70f45), shipped v2.2.2.2.
- [x] Monthly-salary double-charge gremlin (100d3c6): monthly-salary mode no longer double-charges wages. DONE.
- [x] Legendary tier (fast-track F1): 4th tier with the LOCKED values. DONE (d20da2f), shipped v2.2.2.2.
- [!] ProStaff modifiers (Point 5): read getWageModifier / getFatigueRecoveryBonus / getFatigueMitigation in calculateLaborCost and fatigue recovery; neutral 1.0 when ProStaff absent. Blocked on the ProStaff build (brief pulled, under re-review).
- [x] 2026-07-26 bug sweep: WC-001 / WC-002 / WC-003 fixed and merged to main.

## Mid-term (this season)
- [x] Bedrock migration: StateLedger (4328920), NetworkSync v2 (c179141), MasterHUD roster panel (4b10bd5), SettingsHub (ff35ed0). DONE, shipped v2.2.2.2, addMoney hook intact. (ESC WorkerSettingsUI removal still open.)
- [~] Companion read API: 6 functions on `workerCostsManager`. Partial: getWorkersForFarm shipped (90ce2e1); the rest pending DairyCore/ProStaff.

## Long-term / aspirational
- [x] Billing-model change: real-time to per-in-game-day billing on the day tick. DONE (0c808d1), shipped v2.2.2.2.

## Cross-mod / ecosystem dependencies
- [!] Reads ProStaff (`proStaffManager`): getLevel, getWageModifier, getFatigueRecoveryBonus, getFatigueMitigation. Pending the ProStaff build.
- [ ] Read by DairyCore (worker tier), TaxMod (wage totals), WorkplaceTriggers.
- [x] All four bedrock migrations DONE (StateLedger / NetworkSync / MasterHUD / SettingsHub), shipped v2.2.2.2.

## Deferred / parked
- Billing-model decision RESOLVED (per-in-game-day, middle path) and built; no longer parked.

## 2026-08-06 (Fred): Esc RF deep-desk door restored
- [x] When the RF Esc door is live, the Worker Manager (all four tabs: Dashboard, Wage Settings, Worker Stats, About) was unreachable without the Farm Tablet. A bottom-bar "Open Worker Manager" button (MENU_ACTIVATE) on the Esc panel now calls `g_gui:showGui("WCGui")` when `g_wcGui` is present. The button is present in every mod's RfPdaMenuPage copy so it works whether WorkerCosts hosts the Esc door or is a guest. In-game observation still pending.

## 2026-08-07 (Fred): module page dots always visible
- [x] The Esc RF module selector hid its page dots when Worker Costs or Market Dynamics was the active module. Soil and Crop Stress always showed theirs, so WC never read as the 3rd module and the left panel was inconsistent. All four RfPdaMenuPage copies now keep the dots visible (dots = N, chrome unchanged, per the esc-rf-pda umbrella brief). Built, deployed, PR open.
