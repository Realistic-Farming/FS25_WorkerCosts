# Changelog

All notable changes to FS25_WorkerCosts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

### Added
- Changelog file established (suite ruling 2026-08-22).
- Playtest fixes: wage rate reads plain level/custom rates directly, dropping the option-scaling spine multiplier.
- Control Center action: `WC_OPEN_ROSTER` opens the Worker Costs roster from the suite Control Center (requires SettingsHub).

### Fixed
- **Multiplayer security: hiring and firing now charge the farm of the player who asked, never a farm named by the client.** A modified client could hire into another farm's roster at that farm's cost, or fire at its cost; on both network routes the server now takes the farm from its own record of the sender, refuses a sender it cannot place or a spectator, and refuses a request that names a different farm. The host's own hiring and firing are unchanged.
- Monthly cost summary read server-snapshot `monthlyCosts` entries as raw numbers; they are tables with an `amount` field. The accrued monthly total now reads correctly.
- RSF-F201: cab and on-foot controls stay valid across vehicle entry and exit. Each input context now registers through its own private target, so the PLAYER and VEHICLE registrations no longer share one engine identifier that a cab rebuild wiped. Membership is checked in the wrap's own context, a complete set costs no registration work, and the input wrappers install once per session instead of being restored on every mission teardown. The vehicle hook no longer clears the PLAYER roster handle on every seat change.

## [2.2.3.45] - 2026-08-22

- First entry under changelog tracking.
