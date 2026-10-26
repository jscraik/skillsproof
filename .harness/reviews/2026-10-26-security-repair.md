# Local repair of three CodeRabbit findings

## Scope and outcome

All three findings were reproduced against the local `codex/release-safety`
checkout at `0257c7c`, then repaired with focused regressions. This differs from
the CodeRabbit scan revision `6b9b93e5`; the affected patterns were verified in
current source. The delivery candidate is based on `6b9b93e5` on branch
`codex/security-scan-fixes`; it preserves the newer command-evidence regex
grouping correction from main. No paid service, real Tessl command, hosted
recheck, installation or app relaunch was used for validation.

## Reproductions and repairs

- `Sources/SkillsBarCore/Shell.swift`: both valid JSON containing 30,000 opening
  braces in a string and 30,000 unmatched braces exceeded a three-second child
  process deadline. The getter now parses complete JSON first, then scans
  disjoint outer objects once while preserving quote/escape state. It no longer
  retains all candidates or promotes nested fragments from malformed objects.
  Both hostile inputs now finish within the same deadline. Compatibility tests
  cover complete objects/arrays, noisy output, separate malformed/valid objects,
  quoted braces, escapes and rejection of malformed outer objects.
- `verification/prototypes/prototype.js`: a quote-bearing path caused a harmless
  injected `printf` to execute and changed the argument supplied to a stub
  `tessl` shell function. Display and clipboard now share a POSIX-quoted command
  builder. Four shell round trips preserve spaces, quotes, metacharacters and
  the existing home-prefix expansion; displayed and copied text agree.
- `script/validate_pr_template.py`: unterminated comments and fences containing
  20,000 spaces each exceeded three seconds. Bounded delimiter scans replace
  both overlapping regular expressions. Existing comment/fence behaviour and
  all template-validator regressions pass.

## Validation

Commands run from the SkillsProof repository root:

- `python3 script/test_json_security.py` -> fail before repair (both subprocess
  deadlines); pass after repair (one test with two hostile-input subcases).
- `python3 script/test_security_regressions.py` -> fail before repair (both
  malformed-delimiter deadlines); pass after repair (two tests).
- `node script/test_prototype_commands.cjs` -> fail before repair (injected
  output and corrupted argument); pass after repair (four path round trips).
- `python3 -m unittest discover -s script -p 'test_*template.py'` -> pass, 15 tests.
- `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md`
  -> pass.
- `node --check verification/prototypes/prototype.js` -> pass.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/skillsproof-security-clang XDG_CACHE_HOME=/private/tmp/skillsproof-security-xdg swift test --build-system native --disable-sandbox --build-path /private/tmp/skillsproof-security-build --filter CommandJSONTests`
  -> initial fail: one new test supplied malformed JSON due to a missing escaped
  backslash. Corrected the fixture; the full-suite command below includes it.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/skillsproof-security-clang XDG_CACHE_HOME=/private/tmp/skillsproof-security-xdg swift test --build-system native --disable-sandbox --build-path /private/tmp/skillsproof-security-build`
  -> pass, 124 tests, two skips, zero failures. Skips: opt-in live integration
  and unavailable managed PyYAML Python. SwiftPM emitted cache-access and build
  system deprecation warnings; no dependencies were added or downloaded.
- `git diff --check` -> pass.

## Independent review

Final delivery validation on current main:

- `PYTHONDONTWRITEBYTECODE=1 python3 script/test_json_security.py` -> pass, one test with two hostile-input subcases.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/skillsproof-security-clang XDG_CACHE_HOME=/private/tmp/skillsproof-security-xdg swift test --build-system native --disable-sandbox --build-path /private/tmp/skillsproof-security-pr-build`
  -> pass, 125 tests, two skips, zero failures. The skips remain opt-in live
  integration and unavailable managed PyYAML Python.

Reviewer: independent Codex subagent `/root/security_review`, 26 October 2026.
Result: no actionable findings in the three repairs and four regression files.
The reviewer checked both the original local candidate and the isolated delivery
candidate based on `6b9b93e5`. Six files were byte-identical; the validator also
preserved main's unrelated command-evidence grouping repair.

Independently run on the delivery candidate:

- `PYTHONDONTWRITEBYTECODE=1 python3 script/test_security_regressions.py` -> pass, two tests.
- `node script/test_prototype_commands.cjs` -> pass, four shell round trips.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s script -p 'test_*template.py'` -> pass, 17 tests on current main.
- `git diff --check` -> pass.

Reviewed file SHA-256 digests:

```text
9ed3646d93d17c7f81b5db166feec479c3422460257778d070fc7e77e36a5cc4  Sources/SkillsBarCore/Shell.swift
88b3c395f8a2d72e9983d0e70413ef2c805e9ad5e7a18cb6e9e2a46bcd5714e1  script/validate_pr_template.py
a24df55fb6c9ebcd43a3678370656aee1df04213c129e24b77b7837a72769fbe  verification/prototypes/prototype.js
e6f81605622ba9b8056bb5ae5d2f568b7edbd101adfba27a55afe84d3642b2fb  Tests/SkillsBarCoreTests/CommandJSONTests.swift
d7394c62506cfbba918f60af12be3f1479dd33334ddd908983ba25d741665da4  script/test_json_security.py
e8b7589f054c045803876a20937efa9e2cf124063dc8d4c42b6db0466dba3483  script/test_security_regressions.py
f32962397cfde39cbc9171a4d6997fc14ced238162eb95f4ed2f7e6b7c19192c  script/test_prototype_commands.cjs
```

The reviewer did not independently compile Swift or run browser visual checks.
This local review is separate from authenticated hosted bot clearance and CI.

## Boundaries and sibling sweep

Searched native sources, prototype JavaScript and Python scripts for JSON
candidate extraction, command quoting and the affected delimiter patterns.
Both prototype builders were fixed together. Native `DashboardLoader.shellQuoted`
already escapes single quotes correctly and was left unchanged. The two
overlapping validator regexes were removed; no other jsonCandidates
implementation remained. Avoid repeated overlapping scans of untrusted input,
and build displayed/copied shell commands through the same quoting boundary.

Tests exercise production parser code and the prototype's real rendering and
clipboard handler definitions, using a minimal DOM harness and a harmless shell
function. Browser startup/visual acceptance and runtime exploitation against the
installed app were not performed. CodeRabbit findings remain open remotely;
local tests do not establish hosted clearance or merge readiness.
