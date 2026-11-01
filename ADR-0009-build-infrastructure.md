<!--
   - This Source Code Form is subject to the terms of the Mozilla Public
   - License, v. 2.0. If a copy of the MPL was not distributed with this
   - file, You can obtain one at http://mozilla.org/MPL/2.0/.
   -->

# ADR-0009: Build infrastructure

- Status: accepted
- Date: 2026-11-01
- Deciders: project owner

## Decision

**$0 infrastructure ceiling.** No budget for runners. 
**Primary (zero-cost):** Create/push to a public repo under a namespace you control (personal account or new org you own). A repo you own has Actions enabled by default for public repos; standard GitHub-hosted runners including macOS are free for public repositories. No org policy, no billing.
**If you have admin on `BMO-can-code` and can enable it:** use it. If not, mirror becomes primary and old repo becomes read-only upstream.
**Not viable:** Blacksmith/Depot/larger GitHub runners cannot bypass org-level Actions disablement (they are runner providers for GitHub Actions). Rented Macs, self-hosted paid runners are ruled out permanently due to $0 ceiling.
**Fallbacks:** non-GitHub CI only if free; otherwise impossible. **No Linux cross-compile for M1** (compile gate only).
**Constraint:** The repo must be **public** for free macOS minutes. If anyone requires a private repo, the $0 constraint and macOS CI are mutually exclusive.

## Context

Repo `BMO-can-code/desktop` is public. `actions/permissions` show enabled but `POST .../workflow-dispatch` returns `422 "Actions has been disabled for this repository."` — likely org policy. Previous run succeeded, so policy flipped.

## Plan

1. **Immediate (0-24h):** Check if we have admin on `BMO-can-code`. If yes, enable Actions in Org Settings → Actions → Policies. If no, send request today with hard 24-hour deadline and name owner.
2. **Make CI-agnostic:** Extract pipeline to `scripts/ci/build-macos.sh` (env vars only, no `$GITHUB_*`, no `actions/*`). Thin workflow wrapper can call it. Script must run unchanged on Actions, Buildkite, or rented Mac over SSH.
3. **If deadline passes:** Rent a cloud Mac for **one** verified build (~$1-3/hr, ~$10 for 3.6h). Report cost before provisioning. Do not idle.
4. **If cadence > 2 builds/week:** Price self-hosted Mac mini with persistent objdir (5-15 min incremental vs 3.6h) and bring numbers before provisioning.

## Packaging requirements
- Select bundle by **identity**: iterate `.app` bundles, require `Contents/MacOS/<binary>` exists AND `CFBundleIdentifier` matches expected app id. Fail loudly on zero or multiple matches. Never fall back to "first non-helper".
- Ad-hoc sign: `codesign --force --deep --sign -`, verify with `codesign --verify --deep --strict`
- `plutil -lint` on Info.plist
- `ditto -c -k --sequesterRsrc --keepParent`
- Verify: `unzip -l | grep Contents/MacOS/<binary>`, run `<binary> --version`
- Emit artifact manifest: bundle id, version, `lipo -archs`, SHA-256, size

## Cost ceiling
- GitHub macOS (if available): free (public) but disk limited
- Rented cloud Mac (one-off): report cost first, target <$15
- Blacksmith/Depot: not applicable while Actions disabled

## Escalation deadline
24 hours from now. Report admin outcome and decision before renting anything.
