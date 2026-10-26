# SkillsProof

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/jscraik/skillsproof?utm_source=oss&utm_medium=github&utm_campaign=jscraik%2Fskillsproof&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

Every step. Every fault. One glance.

Previously SkillsBar. Internal Swift module names, bundle identity, environment variables and evidence schemas retain their existing identifiers.

SkillsProof is a native macOS menu-bar app for watching local Skills SDK evidence without flattening separate proof lanes. It renders the selected skill's canonical package identity, validation, security, eval preparation, durable downstream receipts, runtime proof, inventory, and Tessl registry state in a compact SwiftUI popover.

The native Guided evidence layout offers a nine-gate overview, searchable skill
and plugin chooser, and individual gate details with persistent navigation.
One Tessl results card stays visible alongside those views. Blue indicates
selection independently of evidence status colours. All displayed native results
come from the dashboard loaders; the browser prototype remains illustrative.

The app is currently a local prototype with a release-capable packaging path. It builds and launches from this checkout, reads the agent-skills repository on disk, and keeps local SDK evidence separate from Tessl registry evidence. A public release still requires Jamie's Developer ID certificate and Apple notarization credentials.

## What It Shows

- **Candidate identity** from the non-mutating `./bin/ask sdk package build <skill> --json --robot` receipt and its canonical `package_digest`.
- **Mechanical validation** from both `./bin/ask skills package verify <skill> --json --robot` and `./bin/ask skills audit <skill> --level strict --json --robot`.
- **Local security posture preview** from the candidate-bound `./bin/ask sdk security risk-modes <skill> --preview --json --robot` receipt. This is advisory; gate 3 proof requires the full governed security receipt.
- **Eval preparation** from scenario-quality, scorer-quality, and scorer-calibration preview receipts collected in the same refresh window.
- **Eval local, Eval cloud, and Tessl staging proof** from the canonical `.harness/evidence/handoff/<skill>/gate-chain.json` and its governed release receipts.
- **Runtime truth** from `.harness/evidence/runtime-proof/<skill>/<runtime>/runtime-card.json` only when the card proves the installed digest, doctor result, and observed behavior for the current package digest.
- **Skill inventory coverage** by scanning `Skills/**/SKILL.md` in the configured agent-skills repository.
- **Installed skill discovery** from `~/.codex/skills`, `~/.agents/skills` and `~/.codex/plugins/cache/<provider>/<plugin>/<version>/skills`. The chooser identifies standalone origins and plugin versions. This is filesystem inventory, not proof of activation in Codex.
- **Tessl registry status** when the `tessl` CLI is available, authenticated, and registry search succeeds.

These lanes are intentionally independent. Every downstream receipt must use the canonical gate-chain order, remain inside the configured repository, include its proof and non-proof boundaries, resolve every evidence reference, and carry exactly the current package digest. Eval local, Eval cloud, and Tessl staging must also identify the same scenario set. Missing, malformed, unbound, or mixed-digest evidence stays unproven or stale. A clean registry result does not prove local source safety, and local build or test proof does not prove hosted CI, registry publication, notarization, or review readiness.

## Requirements

- macOS 14 or newer.
- SwiftPM from Xcode or the active developer toolchain.
- Installed skills in the home locations below. A local agent-skills checkout is optional for inventory and required for the source SDK evidence route. SkillsProof discovers a checkout from the working directory or uses `AGENT_SKILLS_ROOT` when set; no fixed checkout location is assumed.
- Optional: `tessl` CLI access for live registry status.

SkillsProof is not App-Sandboxed: it reads the configured Skills SDK checkout and runs its read-only SDK checks locally. For Tessl, it prefers `TESSL_BIN` when set, then the current user's `~/.local/bin/tessl`, then `PATH`. Keep `SKILLSBAR_REVIEW_FIXTURE` unset for normal use; that variable is reserved for deterministic tests and mockup work.

SkillsProof never automatically runs provider-backed `oss-local` or `oss-cloud` evals, Tessl staging/publication, runtime installation, or runtime-proof commands when the menu opens. Those operations may cost money, require credentials, or mutate external/runtime state, so the app consumes their durable governed receipts instead. A live Tessl CLI search is a registry observation even when the result has a version mismatch or no version. Candidate-bound publication/score receipts, package/registry version equality, and governed registry visibility remain requirements for promotion and identity verification.

## Run

```bash
cd /Users/jamiecraik/dev/skillsbar
./Launch.command
```

You can also double-click `Launch.command` in Finder.

The 04B focus navigator presents all nine evidence stages in a three-column grid.
Select a stage to inspect its full status, next action, and command. Inspection
does not change the next required stage or promote evidence. Refresh preserves
manual selection for the same candidate and resets it for a new candidate.
Expand **Show command** to inspect and select the command before copying;
copying never executes it. Registry details live in a separate disclosure.
Observation, path, and profile copy actions are available in **More…**.
The 460 × 586-point popover adapts to the screen height and scrolls its content.
For visual comparison with 04B, add `--snapshot-focus-reference` to a `--snapshot` command. This uses synthetic stage-three data only for the image; live evidence is unchanged.
The compact grid uses amber for the selected next-required stage and blue for
inspection of another stage. Keyboard focus has a separate neutral outline.
The summary distinguishes passed, review, blocked, stale, and awaiting-proof
states. Severity badges and the blue copy action follow the selected 04B mockup.
Stage changes and arrow-key navigation are immediate. More actions and skill
selection live in the header ellipsis menu; the footer's checked-time row
refreshes evidence. Escape closes the popover.

The launcher serializes concurrent builds, stops an existing instance, delegates bundle construction to `script/package_app.sh`, signs the development app ad hoc, opens it through LaunchServices, and verifies that the process remains running. If LaunchServices is unavailable in the caller's session, it falls back to launching the bundled executable directly and records which path was used. The default build root is:

```text
~/.codex/usage-data/skillsbar
```

For the supported hackathon walkthrough, launch the real menu-bar app with deterministic demo evidence:

```bash
./script/build_and_run.sh --demo
```

This mode launches the packaged `MenuBarExtra` with a deterministic Gate 1 nine-gate fixture. It prefers LaunchServices and accepts the launcher's sustained direct-executable fallback when LaunchServices is unavailable; the receipt records the exact method. Click the Skills SDK document icon in the macOS menu bar to reveal it. The receipt also records `evidence_mode` as `deterministic_demo_fixture`; the fixture demonstrates the product flow but is not live SDK, Tessl, hosted CI, notarization, or review-readiness proof. Use `--verify`, rather than `--demo`, when LaunchServices itself is the behavior under test.

The timed judge walkthrough and proof-boundary answers are in [`DEMO.md`](DEMO.md).

For a build-only check that does not open the app:

```bash
NO_OPEN=1 ./Launch.command
```

Every launch attempt writes `SkillsBar.launch-receipt.json` in the build root. The receipt distinguishes a LaunchServices launch, a direct-executable fallback, and a blocked launch. A direct fallback is useful for headless development automation, but `script/build_and_run.sh --verify` accepts only a sustained LaunchServices launch as live MenuBarExtra evidence.

To package without launching:

```bash
script/package_app.sh debug
```

Set `ARCHES="arm64 x86_64"` and use the `release` configuration to create a universal local package. This remains ad hoc signed unless `SKILLSBAR_SIGNING=identity` and `APP_IDENTITY` are supplied explicitly.

## Distribute

`script/release.sh` is the production distribution boundary. It creates a universal release build, signs with hardened runtime and a timestamp, submits it to Apple notarization, staples the ticket, verifies the signature and distribution policy, and produces a `ditto` zip under `dist/`.

Release builds ignore demo, review and Tessl fixture environment switches and
disable snapshot entry points. Debug builds retain those design tools, with
Tessl fixtures labelled as simulated evidence. Installed-skill discovery uses
the current user's home; `AGENT_SKILLS_ROOT` selects an explicit SDK source
checkout. No workstation-specific source checkout is assumed.

To build and check a local release without replacing or stopping the running
app, use `./script/package_app.sh release /path/to/isolated-build-root`.
Release packaging strips debug/local symbols and runs
`python3 script/check_release.py /path/to/SkillsProof.app` before promoting the
staged bundle. This checks packaged files for personal home paths and fixture
switches, then probes the release executable with fixture overrides enabled.
It also verifies bundled resources are available. An ad hoc local build does
not establish Developer ID signing, notarisation or distribution acceptance.

Store notarization credentials in a keychain profile once:

```bash
xcrun notarytool store-credentials skillsbar-notary
```

Then release with the exact Developer ID identity installed in Keychain Access:

```bash
APP_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
NOTARY_PROFILE=skillsbar-notary \
SKILLSBAR_BUNDLE_ID="com.yourcompany.skillsbar" \
script/release.sh
```

The interactive prompts store the Apple ID, team ID, and app-specific password in the login keychain. The script fails before publication when the identity or keychain profile is absent. It does not create a GitHub release, update feed, Homebrew cask, or automatic-update channel; those are deliberately deferred until SkillsProof has a stable public bundle identifier and a first notarized artifact.

## Configure The Data Source

By default, SkillsProof discovers installed skills in the current user's home.
It can also locate a source checkout from the working directory by looking for
`Skills/agent-ops/improve-agent-native/SKILL.md`. Set `AGENT_SKILLS_ROOT` to use
a source checkout explicitly; no particular username or checkout location is
assumed.

Use another agent-skills checkout:

```bash
AGENT_SKILLS_ROOT=/path/to/agent-skills ./Launch.command
```

Use another skill:

```bash
AGENT_SKILL_PATH=Skills/agent-ops/technical-writer/SKILL.md ./Launch.command
```

`SELECTED_SKILL_PATH` is also accepted for the selected skill path. Paths may identify an existing `Skills/**/SKILL.md` in the configured source root or an absolute `SKILL.md` discovered in the home locations above. SkillsProof follows symlinked installed packages and deduplicates their aliases within the installed inventory. The singular `~/.agent/skills` and `~/.codex/plugin` directories are not the installed locations on this workstation.

Without a saved or explicit selection, SkillsProof chooses a discovered installed skill before falling back to the source checkout's default. A missing saved selection falls back to an existing installed skill. Installed selections work without an agent-skills checkout. Without a checked-source link, all nine stages remain Unproven; **Copy command** only inspects the skill. Independently, SkillsProof looks up `jscraik/<skill-name>` through the existing Tessl reader and displays registry observations only from an exact package match. Registry scores and version comparisons do not establish installed-copy identity or clear SDK gates.

### Link an installed plugin to checked source

SkillsProof uses Skills SDK's `validate-plugin` and `--verify-evidence` contracts,
not an app-owned validator. Run `python3 script/link_installed_source.py --help`
for the local link helper. Supply the trusted SDK CLI, source plugin directory,
installed plugin version directory, forty-character source revision and link
storage directory (`~/.codex/usage-data/skillsbar/source-links`). The helper
captures source through the SDK, verifies that capture against both source and
installed plugin, and saves the link only if all three SDK calls pass. Neither
package is modified. Captures and links are local runtime data; keep them out of
Git and outside the package being captured.

On refresh, the app asks the SDK to verify both copies again against the retained
capture. The nine stages remain full SDK lifecycle evidence gates. Exact binding
and structural checks are partial evidence: Identity also needs provenance,
rights and ownership; Validation also needs applicable quality, reference and
presentation evidence. These observations remain Review required (or Held behind
an incomplete upstream gate), with missing requirements in their details. The
remaining seven stages stay Unproven until their own supported SDK evidence is
linked. Scores are not invented from a structural pass.

An optional `--source-review <absolute-path>` attaches a separately supplied,
candidate-bound `skillsbar-source-review/v1` ownership/provenance review. It must
record owner, maintainer, rights basis, source, revision limits, reviewer and
hashed supporting evidence. SkillsProof rechecks its candidate/mode binding and
supporting hashes after fresh SDK copy verification. This can clear Identity as
recorded provenance; it does not authenticate rights or imply a clean commit.
Retained validation findings block Validation. Structural, content, presentation
and whole-plugin aggregate outcomes remain distinct; an aggregate scenario
blocker belongs to Eval preparation, not a retroactive structural failure.
With no retained findings, an optional `validation_proof` can supply the complete
plugin presentation receipt and one content-review receipt for every direct
child. Their hashes must be listed in the source review. The bundled read-only
bridge uses the linked SDK's Python environment to validate the full SDK
contracts and freshly reassess actual source with those supplied approvals and
assessments. All results must match before Validation can pass. A summary-only
receipt, retained assessment gap, foreign child or incoherent approval cannot
clear the gate. This is separate from scorer calibration and matched evaluation.

Missing or changed captures, mismatched copies, invalid SDK output and failed
verification remove clearance and show Stale. The observer includes hidden files,
permission metadata and removals for both linked packages and the link store,
then schedules fresh SDK verification. Metadata watching is a refresh aid, not an
atomic filesystem or byte-integrity guarantee. Local source revision is a caller
binding; a matching capture does not certify clean Git history or provenance.
The app never automatically runs provider evals, publication or installation.

When no launch-time skill path is set, use **… → Select skill**, then the source, shared-skills or plugin-version submenu, to choose a skill; SkillsProof persists that choice. A launch-time `AGENT_SKILL_PATH` or `SELECTED_SKILL_PATH` intentionally pins the selection. The app refreshes the selected skill immediately after its directory changes, and also refreshes on its five-minute live-data interval.

If Tessl is installed outside the normal user-local location, point the app at it explicitly:

```bash
TESSL_BIN=/absolute/path/to/tessl ./Launch.command
```

For fixture-based Tessl UI work, set `TESSL_REGISTRY_FIXTURE=1` or `TESSL_REGISTRY_FIXTURE_SCORE=<0-100>` with the optional fixture variables used in `DashboardLoader.swift`. Add `TESSL_REGISTRY_FIXTURE_MODE=cached` to exercise the CLI-unavailable historical treatment.

For product demos, use the supported `./script/build_and_run.sh --demo` path above. For deterministic test and mockup work only, `SKILLSBAR_REVIEW_FIXTURE=live` (or `1`) bypasses live package, scenario, security, and registry parsing before constructing the model, so snapshots consistently render the nine-gate implementation state, held local observations, registry score 66, and the canonical SDK-start command. Use `SKILLSBAR_REVIEW_FIXTURE=no-cli` to render the same last-known registry metrics with `CLI UNAVAILABLE` and `Historical external baseline · not proof for this candidate.`

Use `SKILLSBAR_REVIEW_FIXTURE=reference` only to review the tall visual composition against the approved design. It renders Gate 05, live-looking Tessl metrics, and the expanded utility panel as a **visual fixture**; it never substitutes for the selected skill's real evidence or registry state.

A successful live Tessl CLI search stores only sanitized registry fields (version, score, Quality, Impact, Security, eval count, multiplier, and visibility) in local preferences. If the CLI later becomes unavailable, SkillsProof can show that last-known snapshot as historical context. It does not cache credentials, raw command output, or package contents, and cached registry data never promotes a local pipeline gate.

`Tests/SkillsBarTests/Fixtures/` retains sanitized Tessl responses for Private, Public, and missing-visibility registry records. The focused popover tests also render the production `DashboardView` and compare it with the retained implementation snapshot, so model-contract and visible-layout drift fail together.

Security presentation is severity-first and shared by local and registry evidence: failed/critical is red, flagged is amber, advisory is cyan, passed is green, and unknown is pending gray. The test fixtures include an ambiguous registry payload to prove unrelated nested fields cannot override the canonical result. Adaptive render coverage exercises advisory, public, missing-visibility, accessibility-sized text, Reduce Transparency, and Increased Contrast variants.

## Validation

Run the narrow checks first, then widen only when the changed surface requires it.

The repository-owned pull-request contract can be checked without SwiftPM or
third-party dependencies:

```bash
python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md
python3 script/test_validate_pr_template.py
```

To validate a completed PR body, keep the body file inside the checkout and
run:

```bash
python3 script/validate_pr_template.py --body-file .pr-body.md --json
```

The validator proves local template shape and body-format rules only. It does
not prove hosted CI, GitHub review state, merge readiness, or release status.

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
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --build-system native --disable-sandbox --build-path /private/tmp/skillsbar-test-build
```

`script/build_and_run.sh --verify` launches the app and checks for a running `SkillsProof` process. Use it only when a live macOS UI launch is appropriate for the current task.

### Factory validation and Mac acceptance

Automatic Tessl Factory launches are stopped by the empty `triggers` map in
`tessl.json` once that configuration reconciles from the default branch.
The retained actions do not launch from labels, reviews, comments or check
results without triggers. Existing runs are not cancelled by this change;
verify their state separately. Restoring triggers requires explicit approval.
The previous workflow implemented issues labelled `tessl` and shepherded
review and check events on eligible PRs. For any authorised manual run, keep
each issue small, name its allowed files and deterministic checks, and record
any cloud-toolchain blocker instead of claiming a test passed. Do not install
Linux Swift expecting AppKit or SwiftUI macOS builds to work.

`.circleci/config.yml` provides the CircleCI validation workflow:

- **Native macOS tests:** CircleCI macOS with Xcode 26.4.1 on `m4pro.medium`.
  It builds, runs `ReviewPopoverTests` and the full deterministic suite, and
  renders an app fixture. Rendering failures stay failures with logs retained.
  CircleCI explicitly unsets `SKILLSBAR_LIVE_INTEGRATION` and
  `SKILLSBAR_REVIEW_FIXTURE`, so this lane does not run live integration tests.
  Elsewhere, the opt-in live integration test reads the configured agent-skills
  checkout and Tessl surfaces; it does not assert authenticated Tessl access.
  The optional managed-Python shell probe also
  skips when its workstation-only Python path is absent. Neither skip removes
  SwiftUI/AppKit rendering coverage. CodeQL remains separate.
  The native job also runs release-artifact rejection tests, the release safety
  tests, and isolated release packaging with its executable safety probe.
- **Demo site tests:** CircleCI's pinned `cimg/node:22.14.0` installs the npm lockfile,
  provisions Playwright's `chrome` channel, lints, runs `npm test` (which already
  builds), then browser-tests that build through the production server. Server
  readiness has a 60-second limit; the test runner cleans up its owned process
  groups. Logs and success/failure screenshots use portable `outputs/ci` paths.

- **CodeQL:** a separate macOS job analyses Swift with the checksum-verified
  pinned CodeQL bundle and uploads SARIF to GitHub. The upload token belongs
  only in the project-restricted `skillsproof-codeql` context, which is
  attached to this job. Native and site jobs do not request that context.
  Hosted settings verified on 22 October 2026 restrict the context to this
  project and contain `CODEQL_GITHUB_TOKEN`; the project environment has no
  copy. Recheck those hosted settings when changing credential configuration.

The native and site jobs record the checked-out Git revision and tool versions.
CircleCI records the checked-out revision; it does not establish proof for an untested
merge result. The cutover removes both GitHub Actions workflows after the
replacement native, site and CodeQL lanes passed on the migration PR.
Artifacts prove builds, tests and rendered fixtures. They do not prove live
menu-bar interaction, final visual acceptance, registry publication or deployment.

For web changes Tessl can run, from `sites/skillsbar-walkthrough`:

```bash
npm ci
npm run lint
npm test
node scripts/test-browser-production.mjs
```

The last command runs `npm run start -- --port 3008` and the existing
`npm run test:browser -- http://127.0.0.1:3008/`. `BROWSER_ARTIFACT_DIR` selects
the screenshot/log directory (default `outputs/browser`). The Chrome channel
must be installed; CI explicitly uses
`npx --no-install playwright-core install --with-deps chrome`.
Tessl's cloud may inspect native source and run available static checks, but
must leave native compile/test proof to macOS when Apple's SDKs are absent.

Final native acceptance remains supervised on Jamie's Mac: record the checkout,
revision and bundle, open the affected popover state, and check pointer/keyboard
behavior, tooltip/copy feedback, clipping and relevant accessibility settings.
`script/build_and_run.sh --verify` proves a sustained LaunchServices launch;
it does not substitute for those observations. Jamie's Mac is not an unattended
PR runner. These validation jobs use no signing, publication or deployment secrets.

The first bounded factory trial, GitHub issue #19, covers Home and End on the
nine-stage demo grid in `sites/skillsbar-walkthrough/app/focus-navigator.tsx`,
with checks in `tests/browser-smoke.mjs`. Acceptance requires Home to
focus/select the first stage and End the last, while every evidence status
remains unchanged. Arrow navigation and command-textarea editing must continue
to work, with no overflow across existing viewports and passing lint,
rendered-page and browser tests.

After Tessl opens a PR, inspect its head and checks with `gh pr checks` or the
GitHub API, then reconcile them against the job's tested-revision artifact.
The GitHub App's ability to read checks does not prove that the issue-to-PR
starter waits for CI. The shepherd is a separate action. Its previous
90-second debounced triggers handled Tessl PR reviews, human comments and
hosted check results, excluding bot comments. Those triggers are now removed;
comments and check events do not start a round once the default-branch
configuration has reconciled. For any explicitly authorised manual shepherd
run, supervise its reply and new commit, then require fresh checks and
independent review before any merge. Neither a run nor a successful repair is
proven solely by this manifest.

## Project Layout

| Path                                                                                     | Purpose                                                                                                  |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `Package.swift`                                                                          | Swift package definition for the app, core library, and tests.                                           |
| `Launch.command`                                                                         | Build, bundle, sign, and LaunchServices entrypoint.                                                      |
| `script/package_app.sh`                                                                  | Deterministic development/release bundle assembly, architecture verification, and signing boundary.      |
| `script/release.sh`                                                                      | Universal Developer ID signing, notarization, stapling, verification, and release-zip boundary.          |
| `script/build_and_run.sh`                                                                | Convenience wrapper for run, deterministic demo, debug, logs, telemetry, and live verify modes.          |
| `version.env`                                                                            | Shared marketing version and monotonically increasing build number.                                      |
| `Sources/SkillsBar`                                                                      | SwiftUI app, models, services, stores, resources, and views.                                             |
| `Sources/SkillsBarCore`                                                                  | Shared shell execution and JSON parsing helpers.                                                         |
| `Tests/SkillsBarCoreTests`                                                               | Unit tests for core shell behavior.                                                                      |
| `.harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md`                           | Approved current documentation contract for the nine-gate pipeline-posture UI.                           |
| `.harness/media/2026-07-10-skillsbar-pipeline-posture-approved.png`                      | Approved pipeline-posture mockup; supporting visual evidence, not runtime proof.                         |
| `.harness/specs/2026-07-09-skills-sdk-menubar-review-popover-spec.md`                    | Superseded review-popover spec retained as historical/reference-only evidence.                           |
| `.harness/reviews/2026-07-09-review-popover-3lane-synthesis.md`                          | Three-lane implementation handoff for the final-polish review popover refactor.                          |
| `.harness/reviews/2026-07-09-review-popover-pass3-synthesis.md`                          | Pass-three review closeout separating spec/doc handoff defects from remaining implementation blockers.   |
| `.harness/media/2026-07-09-skills-sdk-menubar-review-popover-implementation-handoff.png` | Historical full-height implementation-handoff mockup for the superseded review-popover spec.             |
| `.harness/evidence/2026-07-09-skills-sdk-review-popover-implementation.png`              | Deterministic `404 x 720` app-rendered implementation snapshot; not live MenuBarExtra interaction proof. |
| `.harness/media/2026-07-09-skills-sdk-menubar-review-popover-final-polish.png`           | Earlier final-polish mockup retained as historical comparison evidence.                                  |
| `.harness/media/2026-07-09-skills-sdk-menubar-final-mockup.png`                          | Earlier persisted mockup retained as historical comparison evidence.                                     |

## Development Notes

- Keep menu-bar launch truth, SwiftPM build truth, unit-test truth, live UI proof, Tessl registry proof, and hosted readiness as separate lanes.
- Do not route Computer Use directly through a client notifier from this project; keep Computer Use behind `SkyComputerUseService` when adjacent Codex config work appears.
- Do not edit `.codex/environments/environment.toml` directly; it is generated.
- Treat `.harness` artifacts as supporting project context. Refresh runtime evidence before using the implementation-handoff spec as runtime proof.
- For current UI work, read the approved pipeline-posture spec and mockup first, then inspect `Sources/SkillsBar/Views/ReleaseEvidenceView.swift` and run focused `ReviewPopoverTests`. The 2026-07-09 review-popover spec, mockups, and three-lane syntheses are historical/reference-only material for intentionally retained legacy context; they do not govern new pipeline-posture changes.
- Keep generated app bundles and build output out of the repository; `dist/` is ignored and the default app bundle lives under `~/.codex/usage-data/skillsbar`.
- Keep `Launch.command` as the development runner, `script/package_app.sh` as the sole bundle-construction path, and `script/release.sh` as the credentialed distribution boundary.
- Automatic updates, Homebrew distribution, launch-at-login UI, and hosted release automation should be added only after the first notarized release fixes the public bundle identifier and update ownership. They are delivery features, not substitutes for signing and notarization.

## Proof Boundaries

Passing `swift build`, `NO_OPEN=1 ./Launch.command`, or `swift test` proves only the local lane that command exercises. It does not prove:

- Hosted CI status.
- Tessl private-registry authentication or publication state.
- macOS distribution signing or notarization.
- Review-thread, tracker, or merge readiness.
- Menu-bar visibility on every desktop arrangement.

For UI changes, closeout should include fresh runtime evidence from the live app, not only generated mockups or historical screenshots.
