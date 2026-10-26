#!/usr/bin/env python3
"""Validate SkillsBar's pull-request template and filled PR bodies.

The validator is intentionally dependency-free so it can run on a clean macOS
checkout before SwiftPM is available.  It follows the repository's checked-in
template contract and the corresponding coding-harness contract: section and
field extraction is block-aware, HTML guidance comments cannot satisfy a field,
and command evidence has a machine-readable outcome.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


MAX_BODY_LENGTH = 100_000
REQUIRED_SECTIONS = (
    "## Summary",
    "## Release boundary",
    "## Behavior proof",
    "## Change details",
    "## Checklist",
    "## Validation",
    "## Review and closeout",
)

# These are the fields that form the machine-checked core of the contract. The
# remaining template fields stay available for maintainer context and are
# covered by the template-shape check.
REQUIRED_FIELDS: dict[str, tuple[str, ...]] = {
    "## Summary": (
        "Problem", "Change", "Why this approach", "Intended outcome",
        "Out of scope", "Reviewer focus", "Risk and rollback",
    ),
    "## Release boundary": (
        "Release mode",
        "Completion condition",
        "Deferred work",
        "Stronger-proof condition",
    ),
    "## Behavior proof": (
        "Before",
        "After",
        "Environment or operator path",
        "Verification steps",
        "Evidence after fix",
        "Untested paths and limitations",
    ),
    "## Change details": (
        "Plan IDs",
        "Linear reference",
        "Linked issue relationship",
        "Completed work",
        "Affected surfaces",
        "Documentation impact",
        "SemVer impact",
        "Acceptance trace",
        "Runtime impact",
        "Deferred work",
    ),
    "## Validation": ("Regression coverage", "Untested or blocked paths"),
    "## Review and closeout": (
        "CodeRabbit", "Independent reviewer evidence", "Codex", "CodeRabbit Semgrep",
        "User-facing impact", "Remaining findings or waivers", "Current blockers",
    ),
}

TEMPLATE_FIELDS: dict[str, tuple[str, ...]] = {
    "## Summary": (
        "Problem",
        "Change",
        "Why this approach",
        "Intended outcome",
        "Out of scope",
        "Reviewer focus",
        "Risk and rollback",
    ),
    "## Release boundary": REQUIRED_FIELDS["## Release boundary"],
    "## Behavior proof": REQUIRED_FIELDS["## Behavior proof"],
    "## Change details": (
        "Plan IDs",
        "Linear reference",
        "Linked issue relationship",
        "Completed work",
        "Affected surfaces",
        "Documentation impact",
        "SemVer impact",
        "Acceptance trace",
        "Runtime impact",
        "Deferred work",
        "Validation evidence",
        "Review artifacts",
        "Pattern scope inventory",
        "Meta-behavior proof",
        "Repeated-error research",
        "Durable evidence map",
        "Learning / reinforcement",
    ),
    "## Validation": REQUIRED_FIELDS["## Validation"],
    "## Review and closeout": (
        "CodeRabbit",
        "Independent reviewer evidence",
        "Codex",
        "CodeRabbit Semgrep",
        "User-facing impact",
        "Remaining findings or waivers",
        "Current blockers",
    ),
}

TEMPLATE_PLACEHOLDERS = (
    "pass/fail",
    "<link / artifact path / comment ID>",
    "<reviewer + link>",
    "Add one-paragraph merge rationale here.",
)

RELEASE_MODE_RE = re.compile(r"^(?:Prototype|Portfolio|Product|Harness)$", re.I)
NA_WITH_REASON_RE = re.compile(
    r"^(?:n\.a\.|n/a|not applicable)\s+because\s+(?!reason\b)(?!<reason>\b)\S.{6,}\S$",
    re.I,
)
LINEAR_REFERENCE_RE = re.compile(
    r"^(?:n\.a\.|n/a|not applicable)\s+.{6,}|\b(?:Refs?|Fix(?:es)?|Closes?)\s+JSC-\d+\b",
    re.I,
)
LINKED_ISSUE_RE = re.compile(r"\bJSC-\d+\b", re.I)
ACCEPTANCE_ID_RE = re.compile(r"\b(?:SA|AC|FR|NFR|IU|PU)-\d+(?:-\d+)?\b", re.I)
LOCAL_ABSOLUTE_PATH_RE = re.compile(
    r"(?:^|[\s`\"'(])/(?:Users/|private/(?:var/folders|tmp)/|var/folders/|tmp/)[^\s`\"'<>),;]+"
)
CHECKBOX_RE = re.compile(r"^- \[[ xX]\]")
UNRESOLVED_CHECKBOX_RE = re.compile(r"^- \[ \]")
STATUS_MARKER_RE = re.compile(r"\*\*\((?:pending|n/a|not applicable)\)\*\*", re.I)
NOT_APPLICABLE_RE = re.compile(r"^(?:n\.a\.|n/a|not applicable)(?=$|\s)", re.I)
REQUIRED_CHECKLIST_ITEMS = (
    "I did not push directly to `main`; this PR is from a dedicated branch.",
    "Branch name follows policy (`codex/*` for agent-created branches).",
    "I ran the required validation for the changed surfaces and recorded every outcome below.",
    "CodeRabbit review completed and findings handled or explicitly waived.",
    "An independent reviewer performed the review outside the coding agent.",
    "Codex review completed and findings handled or explicitly waived.",
    "Any CodeRabbit Semgrep findings were fixed or explicitly justified.",
    "Merge is blocked until all required checks pass.",
    "I will delete the branch and worktree after merge.",
)


def strip_comments(value: str) -> str:
    """Remove HTML comments before checking whether a value is populated."""

    return re.sub(r"<!--\s*[\s\S]*?\s*-->", "", value)


def normalize(value: str) -> str:
    """Remove comments and enclosing code markers, then collapse whitespace."""

    value = strip_comments(value).strip()
    fenced = re.fullmatch(r"```[\w-]*\s*([\s\S]*?)\s*```", value)
    if fenced:
        value = fenced.group(1)
    inline = re.fullmatch(r"`([^`]+)`", value)
    if inline:
        value = inline.group(1)
    return re.sub(r"\s+", " ", value).strip()


def extract_section(body: str, heading: str) -> str | None:
    """Return the body below an exact level-two heading."""

    escaped = re.escape(heading)
    match = re.search(
        rf"(?:^|\n){escaped}[ \t]*(?:\r?\n)([\s\S]*?)(?=\r?\n## |\r?\n# |$)",
        body,
        re.I,
    )
    return match.group(1) if match else None


def extract_field(section_body: str, label: str) -> str | None:
    """Extract one markdown bullet without consuming the next bullet."""

    escaped = re.escape(label)
    match = re.search(
        rf"^-[ \t]+{escaped}:[ \t]*([\s\S]*?)(?=\r?\n-[ \t]+[A-Za-z][^\n:]{{0,80}}:|\r?\n##[ \t]|\Z)",
        section_body,
        re.I | re.M,
    )
    return normalize(match.group(1)) if match else None


def field_value(body: str, section: str, label: str) -> str | None:
    """Return a normalized field value, or None if its section or label is absent."""

    section_body = extract_section(body, section)
    return extract_field(section_body, label) if section_body is not None else None


def missing_sections(body: str) -> list[str]:
    """Report required headings that have no matching section in the body."""

    return [
        f"Missing required section: {section}"
        for section in REQUIRED_SECTIONS
        if extract_section(body, section) is None
    ]


def field_errors(body: str) -> list[str]:
    """Report missing or empty required fields and unexplained n.a. values."""

    errors: list[str] = []
    for section, labels in REQUIRED_FIELDS.items():
        section_body = extract_section(body, section)
        if section_body is None:
            errors.append(f"Missing {section[3:].lower()} block.")
            continue
        for label in labels:
            value = extract_field(section_body, label)
            if value is None:
                errors.append(f"Missing required {section[3:].lower()} field: {label}")
            elif not value:
                errors.append(f"Replace {section[3:].lower()} field placeholder: {label}")
            elif NOT_APPLICABLE_RE.match(value) and not NA_WITH_REASON_RE.fullmatch(value):
                errors.append(f"Required {section[3:].lower()} field needs a reason for n.a.: {label}")
    return errors


def release_boundary_errors(body: str) -> list[str]:
    """Check that a supplied release mode is concrete or has an n.a. reason."""

    value = field_value(body, "## Release boundary", "Release mode")
    if value is None:
        return []
    if not RELEASE_MODE_RE.fullmatch(value) and not NA_WITH_REASON_RE.fullmatch(value):
        return [
            "Release mode must be Prototype, Portfolio, Product, Harness, or `n.a. because <reason>`."
        ]
    return []


def checklist_errors(body: str) -> list[str]:
    """Check checklist identity, order, and explicit status for unchecked items."""

    checklist = extract_section(body, "## Checklist")
    if checklist is None:
        return ["Missing checklist block."]
    items = [line.strip() for line in checklist.splitlines() if CHECKBOX_RE.match(line.strip())]
    if not items:
        return ["Checklist has no checkbox items."]
    template_path = Path(__file__).resolve().parent.parent / ".github/PULL_REQUEST_TEMPLATE.md"
    template_checklist = extract_section(read_text(template_path), "## Checklist") or ""
    expected = [line.strip() for line in template_checklist.splitlines() if CHECKBOX_RE.match(line.strip())]

    def item_text(item: str) -> str:
        """Remove checkbox and status markers to compare checklist wording."""

        return STATUS_MARKER_RE.sub("", CHECKBOX_RE.sub("", item)).strip()

    if [item_text(item) for item in expected] != list(REQUIRED_CHECKLIST_ITEMS):
        return ["Checked-in template does not preserve the required checklist contract."]
    if [item_text(item) for item in items] != list(REQUIRED_CHECKLIST_ITEMS):
        return ["Checklist must preserve every template item in its original order."]
    unchecked = [line for line in items if UNRESOLVED_CHECKBOX_RE.match(line)]
    unresolved = [line for line in unchecked if not STATUS_MARKER_RE.search(line)]
    if unresolved:
        return [
            "Checklist has unchecked item(s) without explicit status marker ((Pending) or (N/A)):\n"
            + "\n".join(unresolved)
        ]
    return []


def command_evidence_errors(body: str) -> list[str]:
    """Require command evidence with recognized outcomes and blocked reasons."""

    validation = extract_section(body, "## Validation")
    if validation is None:
        return []
    command_lines = [
        line.strip()
        for line in validation.splitlines()
        if re.match(r"^-\s*Command:\s*", line.strip(), re.I)
    ]
    if not command_lines:
        return ["Validation section must include at least one Command evidence line."]

    outcome = r"(?:pass|fail|`(?:pass|fail)`)(?:\s*\([^)]*\)\.?)?|(?:n\.a\.|n/a|`(?:n\.a\.|n/a)`)(?:\s*\([^)]*\))?|(?:blocked|`blocked`)\s*\([^)]*\S[^)]*\)"
    pattern = re.compile(rf"^-\s*Command:\s*(?:`[^\n`]+`|\S.*?\S)\s*->\s*(?:{outcome})$", re.I)
    errors = []
    for line in command_lines:
        if not pattern.fullmatch(line):
            errors.append(
                "Command evidence must use `Command: <exact command> -> pass|fail`, "
                "`-> n.a.|n/a` (optional reason), or `-> blocked (<required reason>)` format: "
                + line
            )
    return errors


def linked_issue_errors(body: str) -> list[str]:
    """Check issue references and acceptance evidence for completion or deferral."""

    plan_ids = field_value(body, "## Change details", "Plan IDs") or ""
    linear_reference = field_value(body, "## Change details", "Linear reference") or ""
    relationship = field_value(body, "## Change details", "Linked issue relationship") or ""
    acceptance = field_value(body, "## Change details", "Acceptance trace") or ""
    errors: list[str] = []

    if linear_reference and not LINEAR_REFERENCE_RE.search(linear_reference):
        errors.append(
            "Linear reference must use Refs, Fixes, or Closes with a Linear issue key, or n.a. with reason; URL-only references do not satisfy the PR contract."
        )

    if not LINKED_ISSUE_RE.search(plan_ids):
        return errors

    issue_keys = {key.upper() for key in LINKED_ISSUE_RE.findall(plan_ids)}
    for issue_key in sorted(issue_keys):
        if not re.search(rf"\b{re.escape(issue_key)}\b", acceptance, re.I):
            errors.append(
                f"Acceptance trace for linked issue {issue_key} must name the issue and a concrete acceptance ID, or explicitly state the preparatory relationship and that completed acceptance IDs are none."
            )
            continue
        segment_match = re.search(
            rf"\b{re.escape(issue_key)}\b([\s\S]*?)(?=\bJSC-\d+\b|$)",
            acceptance,
            re.I,
        )
        issue_segment = segment_match.group(1) if segment_match else ""
        preparatory = re.search(
            r"\b(?:preparatory|enabling|supporting|governance)\b[\s\S]{0,180}\b(?:relationship|work|change|guard|evidence|contract)\b",
            acceptance,
            re.I,
        ) or re.search(r"\bdoes not complete\b[\s\S]{0,120}\b(?:issue|acceptance)", acceptance, re.I)
        no_completion = re.search(
            rf"\bcompleted\s+{re.escape(issue_key)}\s+acceptance\s+IDs?\s*:\s*none\b",
            acceptance,
            re.I,
        )
        if not ACCEPTANCE_ID_RE.search(issue_segment) and not (preparatory and no_completion):
            errors.append(
                f"Acceptance trace for linked issue {issue_key} must list a concrete acceptance ID or explicitly state the preparatory relationship and that completed issue acceptance IDs are none."
            )

    if relationship and re.search(r"\b(?:preparatory|enabling)\b", relationship, re.I) and not re.search(
        r"\b(?:completed\s+(?:JSC-\d+\s+)?acceptance\s+IDs?\s*:\s*none|does\s+not\s+(?:close|complete))\b",
        relationship,
        re.I,
    ):
        errors.append(
            "Preparatory/enabling linked issue relationship must state completed acceptance IDs are none or explicitly say it does not close the linked acceptance scope."
        )
    return errors


def placeholder_errors(body: str) -> list[str]:
    """Report unresolved template placeholders and nonportable evidence paths."""

    errors = [f"Replace template placeholder: {placeholder}" for placeholder in TEMPLATE_PLACEHOLDERS if placeholder in body]
    review = extract_section(body, "## Review and closeout")
    if review is not None:
        errors.extend(
            f"Replace unresolved placeholder token: {token}"
            for token in re.findall(r"<[^>\n]+>", review)
        )
    if LOCAL_ABSOLUTE_PATH_RE.search(body):
        errors.append("PR body must not include local absolute paths; use repo-relative evidence references.")
    return errors


def validate_body(body: str) -> list[str]:
    """Return contract violations for a filled PR body, ignoring HTML comments."""

    if len(body) > MAX_BODY_LENGTH:
        return [f"PR body exceeds maximum length of {MAX_BODY_LENGTH} characters."]
    if not body.strip():
        return ["PR body is empty. Fill out the full PR template."]
    body = strip_comments(body)
    errors = missing_sections(body)
    headings = re.findall(r"^## .+$", body, re.M)
    if headings != list(REQUIRED_SECTIONS):
        errors.append("Sections must match the template exactly and in order.")
    errors.extend(field_errors(body))
    errors.extend(release_boundary_errors(body))
    errors.extend(checklist_errors(body))
    errors.extend(command_evidence_errors(body))
    errors.extend(linked_issue_errors(body))
    errors.extend(placeholder_errors(body))
    return errors


def validate_template(template: str) -> list[str]:
    """Validate the shape of the checked-in template without filling it in."""

    errors = missing_sections(template)
    checklist = extract_section(template, "## Checklist") or ""
    checklist_items = [
        STATUS_MARKER_RE.sub("", CHECKBOX_RE.sub("", line.strip())).strip()
        for line in checklist.splitlines() if CHECKBOX_RE.match(line.strip())
    ]
    if checklist_items != list(REQUIRED_CHECKLIST_ITEMS):
        errors.append("Template checklist must preserve every required item in its original order.")
    for section, labels in TEMPLATE_FIELDS.items():
        section_body = extract_section(template, section)
        if section_body is None:
            continue
        for label in labels:
            if extract_field(section_body, label) is None:
                errors.append(f"Template is missing required field: {section} / {label}")
    if "- Command:" not in (extract_section(template, "## Validation") or ""):
        errors.append("Template Validation section must document the Command evidence format.")
    if "## Review and closeout" in template and re.search(r"/Users/|/private/(?:tmp|var)/|/tmp/", template):
        errors.append("Template must not include local absolute paths.")
    return errors


def read_text(path: Path) -> str:
    """Read UTF-8 text or exit with a diagnostic when the file cannot be read."""

    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Unable to read {path}: {exc}") from exc


def render(errors: Iterable[str], as_json: bool) -> None:
    """Print validation errors or success as JSON or human-readable text."""

    errors = list(errors)
    if as_json:
        print(json.dumps({"status": "fail" if errors else "pass", "errors": errors}, indent=2))
    elif errors:
        print("PR template validation failed:")
        print("\n".join(f"- {error}" for error in errors))
    else:
        print("PR template validation passed.")


def main(argv: list[str] | None = None) -> int:
    """Validate the selected template or body file and return an exit status."""

    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--template",
        type=Path,
        default=Path(".github/PULL_REQUEST_TEMPLATE.md"),
        help="validate the checked-in template shape (default: .github/PULL_REQUEST_TEMPLATE.md)",
    )
    source.add_argument("--body-file", type=Path, help="validate a filled PR body")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable result")
    args = parser.parse_args(argv)

    if args.body_file is not None:
        errors = validate_body(read_text(args.body_file))
    else:
        errors = validate_template(read_text(args.template))
    render(errors, args.json)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
