# Desktop release implementation plan

**Goal:** Publish blue Windows chrome with signed automatic updates from main, using a local build.

**Architecture:** Reuse native Mica and the Tauri updater. One PowerShell release command owns verification and publication in both local runs and the main workflow.

**Constraints:** Preserve native controls, profile identifier, signing key, draft protection and live-only mailbox storage. Commit only the release's source changes; exclude signing material and generated build overrides.

- [ ] Test caption colors for dark/light Mica and solid fallbacks; replace the accent-colored default fallback with matching colors in `desktop/src-tauri/src/appearance.rs`.
- [ ] Verify GitHub's normalized asset names and align `scripts/desktop-release.test.ts`; allow the release command to pass its derived version to `desktop-release.ts`.
- [ ] Add `scripts/release-desktop.ps1`: require clean current main, derive version from first-parent count, load existing DPAPI-protected signing credentials, run web/native checks, build using a temporary Tauri version override, verify signatures and tamper rejection, publish versioned assets before channel metadata, and refuse channel regression.
- [ ] Reuse the command from `.github/workflows/desktop-release.yml` on every main push and manual dispatch. Document local fallback and legacy one-time install.
- [ ] Run relevant tests, typecheck, lint, frontend/runtime and native checks; inspect the release diff. Commit, integrate into main, build locally, publish and download/verify the public artifacts. Install and inspect desktop behavior if the current session permits safe operation.
