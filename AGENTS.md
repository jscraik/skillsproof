---
schema_version: 2
---

# SkillsProof Agent Instructions

## Scope

These instructions apply to the whole `skillsbar` repository.

SkillsProof is a local macOS SwiftUI menu-bar prototype for Skills SDK evidence visibility. Treat it as a live local app, not as a scratch rewrite. Keep local build, launch, UI, registry, hosted, and review-readiness truth separate.

## Discovery

1. Read this file and `README.md` before editing.
2. Inspect `Package.swift`, `Launch.command`, and the specific `Sources/**` or `Tests/**` files in scope.
3. For UI or behavior work, start with `.harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md`, its approved `.harness/media/2026-07-10-skillsbar-pipeline-posture-approved.png` mockup, the active `ReleaseEvidenceView`, and focused `ReviewPopoverTests`. The 2026-07-09 review-popover spec and its materials are historical reference only; do not use them as the default implementation contract.
4. Treat `.codex/environments/environment.toml` as generated. Do not edit it directly.

## Repo Rules

- Prefer current repo evidence and command output over memory or prior prototype assumptions.
- Preserve unrelated dirty or untracked work. This repository may start on an unborn branch with all files untracked.
- Keep edits narrowly scoped to the requested surface.
- Use the configured non-login shell and invoke shell scripts explicitly with `bash` when running them through automation. Use a login shell only for a bounded shell-startup investigation.
- Use `rg` or `rg --files` for discovery.
- Use `apply_patch` for manual file edits.
- Do not put generated app bundles, SwiftPM build output, raw telemetry, or local-only runtime databases into durable docs or commits unless explicitly requested.
- Do not claim hosted CI, Tessl publication, review-thread resolution, merge readiness, notarization, or UI runtime proof unless that lane was checked in the current closeout window.

## Runtime And Data Boundaries

- Discover installed skills under the current user's home, or locate a source
  checkout from the working directory. Set `AGENT_SKILLS_ROOT` for an explicit
  source checkout; never embed a workstation-specific home path.
- Default selected skill: `Skills/agent-ops/improve-agent-native/SKILL.md`.
- Override the data repo with `AGENT_SKILLS_ROOT`.
- Override the selected skill with `AGENT_SKILL_PATH` or `SELECTED_SKILL_PATH`.
- Default build root: `/Users/jamiecraik/.codex/usage-data/skillsbar`, controlled by `SKILLSBAR_BUILD_ROOT`.
- Computer Use is adjacent workstation infrastructure, not this app's direct runtime path. Keep it routed through `SkyComputerUseService` if related config work appears.

## Validation

Run the narrowest relevant command first:

```bash
HOME=/private/tmp/skillsbar-home \
XDG_CACHE_HOME=/private/tmp/skillsbar-xdg \
CLANG_MODULE_CACHE_PATH=/private/tmp/skillsbar-clang-cache \
swift build --build-system native --disable-sandbox --build-path /private/tmp/skillsbar-native-build
```

```bash
NO_OPEN=1 ./Launch.command
```

```bash
HOME=/private/tmp/skillsbar-test-home \
XDG_CACHE_HOME=/private/tmp/skillsbar-test-xdg \
CLANG_MODULE_CACHE_PATH=/private/tmp/skillsbar-test-clang-cache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --build-system native --disable-sandbox --build-path /private/tmp/skillsbar-test-build
```

For live UI launch proof, use:

```bash
script/build_and_run.sh --verify
```

Report validation as `Command: <exact command> -> pass|fail|blocked (<reason>)`. State what each command proves and what it does not prove.

## Documentation

- Use `verification/prototypes/simplify-evidence.html?v=3` as the design working
  surface. Keep its layout and controls aligned with approved native changes;
  retain explicit simulated-data labels. Design future UI changes there first,
  then promote them to the native app only when requested. Review changed native
  UI through Borumi playback using Emil AI for UI, Emil Kowalski and Interfacecraft;
  a build or still screenshot alone is not recorded visual acceptance.

- The isolated browser design prototype and icon concepts live in
  `verification/prototypes/`. Start with its [reopening guide](verification/prototypes/REOPEN.md)
  and run `python3 verification/prototypes/serve.py` to reopen Guided evidence
  (`http://127.0.0.1:8769/simplify-evidence.html?v=3`). Keep prototype changes
  separate from the native app: do not promote assets, rebuild or relaunch
  SkillsProof without an explicit request. Prototype scores and chooser inventory
  are snapshots/fixtures, not fresh SDK, registry or activation proof.

- README claims must map to live files, scripts, or inspected source.
- Keep local absolute paths explicit when they are true for this workstation-only prototype, but do not treat them as portable release proof.
- For substantial docs, preserve proof boundaries: local build/test evidence, Tessl registry state, hosted CI, and review readiness are separate lanes.

## Harness Context

The `.harness` directory contains project context and design artifacts. The approved pipeline-posture spec is the current documentation contract; its mockup remains supporting evidence, not runtime proof. The earlier review-popover spec is historical reference only. For UI changes that require visual verification, refresh against the live app and report screenshot, clipboard, focus, reduced-motion, and height evidence when applicable.
