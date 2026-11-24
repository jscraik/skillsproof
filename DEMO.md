# SkillsProof Hackathon Demo

## Launch both surfaces

Clone the repository using the [README quick start](README.md#quick-start).
Start each terminal at that checkout's root. The native app needs macOS 14 or
newer and Swift 6.0 or newer; the optional landing page needs Node.js 22.13.0 or
newer and npm.

Start the landing page in Terminal 1:

```bash
cd sites/skillsbar-walkthrough
npm ci
npm run dev
```

Open `http://localhost:3000/` and leave the hero visible. Start the native app in Terminal 2:

```bash
./script/build_and_run.sh --demo
```

Wait for the success message, then leave the app closed in the menu bar until the product reveal. The popover must show `DEMO FIXTURE` and the registry card must show `BASELINE`; these disclosures are the visual boundary between deterministic evidence and live app interaction.

If the icon is hidden by the notch or menu-bar crowding, temporarily quit a few nonessential menu-bar apps before presenting. Do not substitute the static website mockup for the app interaction.

## 90-second site-to-native walkthrough

1. **0–12 seconds — Website wedge.** Keep the hero still. “When a Skill changes, yesterday’s green receipts can still look safe.”
2. **12–22 seconds — Native reveal.** Click the Skills SDK menu-bar icon. “We built SkillsProof to bind every proof gate to one canonical candidate.”
3. **22–42 seconds — Show the decision.** Point to `DEMO FIXTURE`, `Gate 1 of 9`, and `downstream proof held`. “This candidate has no canonical package digest, so none of its downstream evidence can count.”
4. **42–58 seconds — Show the flow.** Scroll from Gates 2–5 toward Gates 6–9. “Validation, security, evaluation, publication, and runtime truth must all bind to that same candidate.”
5. **58–72 seconds — Show the boundary.** Point to `BASELINE`. “The published registry baseline is useful context, but it is not proof about this candidate.”
6. **72–84 seconds — Show the action.** Point to `COPY COMMAND`. “SkillsProof gives the operator the exact next command instead of inventing a green release state.”
7. **84–90 seconds — Close on Codex.** “Codex modeled the contract, implemented the fixture and interface, and proved it with tests and launch receipts.”

Do not run the website’s four-view walkthrough during the core presentation. It is an optional visual explanation for judge Q&A; the native menu-bar app is the product proof.

## Judge questions

- **What is deterministic?** The site walkthrough, the displayed nine-gate candidate state, and the registry card marked `BASELINE`. The native app shell, scrolling, accessibility, and copy interaction are production SwiftUI surfaces.
- **What is live?** The app process and menu-bar interaction. In normal mode, SkillsProof reads current local SDK receipts and Tessl observations; `--demo` deliberately replaces those inputs with a stable fixture.
- **Why Codex?** Codex was used to shape the evidence contract, implement the SwiftUI app and deterministic fixture, write tests, and preserve proof boundaries across the nine gates.
- **What works today?** Local build, deterministic model selection, rendering, scrolling, command copy behavior, and the packaged macOS app. Hosted CI, notarization, registry publication, and review readiness remain separate claims.

## Receipt check

After launch:

```bash
plutil -p ~/.codex/usage-data/skillsbar/SkillsBar.launch-receipt.json
```

Expect `status` to be `launched`, `evidence_mode` to be `deterministic_demo_fixture`, and `launch_method` to be either `launchservices_open` or the explicitly recorded `direct_executable_fallback`.

If you set `SKILLSBAR_BUILD_ROOT`, read the receipt from that directory instead.
The `SkillsBar` receipt name and environment-variable prefix are retained
compatibility identifiers.
