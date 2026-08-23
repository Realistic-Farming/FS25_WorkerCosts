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
- Monthly cost summary read server-snapshot `monthlyCosts` entries as raw numbers; they are tables with an `amount` field. The accrued monthly total now reads correctly.

## [2.2.3.45] - 2026-08-22

- First entry under changelog tracking.
