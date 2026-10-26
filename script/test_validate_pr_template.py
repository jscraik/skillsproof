#!/usr/bin/env python3
"""Focused tests for the dependency-free PR-template validator."""

import sys
import re
import unittest
from pathlib import Path

# Support both `python3 script/test_validate_pr_template.py` and unittest
# discovery from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_pr_template import validate_body, validate_template


VALID_BODY = """## Summary

- Problem: Maintainers need a consistent, evidence-led PR body.
- Change: Add the repository PR template and its local validator.
- Why this approach: Keep the contract in Markdown and enforce the machine-checkable core with a dependency-free script.
- Intended outcome: Incomplete PR bodies fail before review.
- Out of scope: Hosted review or merge readiness.
- Reviewer focus: Template shape and validator behavior.
- Risk and rollback: Revert the template and script together.

## Release boundary

- Release mode: Harness
- Completion condition: The template shape and filled-body validator pass locally.
- Deferred work: Hosted GitHub integration is deferred because this repository has no PR-body workflow yet.
- Stronger-proof condition: A hosted gate or generated scaffold would require a productized integration and additional CI proof.

## Behavior proof

- Before: SkillsBar had no repository-owned PR template validator.
- After: Maintainers can validate the template shape and a filled PR body locally.
- Environment or operator path: Local repository checkout with Python 3.
- Verification steps: python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md.
- Evidence after fix: The validator returned a passing result for the checked-in template.
- Untested paths and limitations: Live GitHub submission is n.a. because this is local contract validation.

## Change details

- Plan IDs: n.a. because no external plan is linked.
- Linear reference: n.a. because no Linear issue is linked.
- Linked issue relationship: n.a. because no issue is linked.
- Completed work: Added the PR template, validator, and focused tests.
- Affected surfaces: .github/PULL_REQUEST_TEMPLATE.md, script/validate_pr_template.py, and script/test_validate_pr_template.py.
- Documentation impact: README.md updated with the local validator command.
- SemVer impact: n.a. because this is repository governance and does not change the packaged app.
- Acceptance trace: n.a. because no external acceptance IDs apply.
- Runtime impact: CI-only and maintainer-tooling; the shipped app is unchanged.
- Deferred work: Hosted PR-body enforcement remains deferred.
- Validation evidence: script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md -> pass.
- Review artifacts: n.a. because no external review artifact exists in this local validation.
- Pattern scope inventory: n.a. because no shared application pattern changed; checked scope is the PR-template contract and no durable destination is needed.
- Meta-behavior proof: n.a. because this PR does not admit repeated steering.
- Repeated-error research: n.a. because no recurrence or safety-boundary trigger applies.
- Durable evidence map: n.a. because the validator output is the direct source-of-truth for this local contract.
- Learning / reinforcement: none with reason; no new project learning is promoted.

## Checklist

- [x] I did not push directly to `main`; this PR is from a dedicated branch.
- [x] Branch name follows policy (`codex/*` for agent-created branches).
- [x] I ran the required validation for the changed surfaces and recorded every outcome below.
- [ ] **(Pending)** CodeRabbit review completed and findings handled or explicitly waived.
- [ ] **(Pending)** An independent reviewer performed the review outside the coding agent.
- [ ] **(Pending)** Codex review completed and findings handled or explicitly waived.
- [x] Any CodeRabbit Semgrep findings were fixed or explicitly justified.
- [x] Merge is blocked until all required checks pass.
- [x] I will delete the branch and worktree after merge.

## Validation

- Regression coverage: Focused unit tests cover template shape, complete bodies, blank fields, release-mode validation, and command evidence.
- Untested or blocked paths: Live GitHub PR submission is n.a. because the validator is local.
- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> pass

## Review and closeout

- CodeRabbit: n.a. because no hosted review has been requested.
- Independent reviewer evidence: n.a. because this local change has not entered review.
- Codex: local self-review only; hosted approval is not claimed.
- CodeRabbit Semgrep: n.a. because no CodeRabbit run exists.
- User-facing impact: no
- Remaining findings or waivers: None.
- Current blockers: Hosted review and CI remain pending.
"""


class PullRequestTemplateValidatorTests(unittest.TestCase):
    def test_missing_or_blank_reviewer_fields_fail(self) -> None:
        """Reject omitted review fields and fields populated only by comments."""
        for label in ["CodeRabbit", "Codex", "Independent reviewer evidence", "CodeRabbit Semgrep"]:
            for replacement in ["", f"- {label}: <!-- no evidence -->\n"]:
                with self.subTest(label=label, replacement=replacement):
                    body = re.sub(rf"^- {re.escape(label)}:.*\n", replacement, VALID_BODY, flags=re.M)
                    self.assertTrue(validate_body(body))

    def test_replaced_removed_or_reordered_checklist_fails(self) -> None:
        """Reject changes to the required checklist wording, membership, or order."""
        items = re.findall(r"^- \[[ xX]\].*$", VALID_BODY, re.M)
        variants = [
            VALID_BODY.replace(items[0], "- [x] Anything at all."),
            VALID_BODY.replace(items[0] + "\n", ""),
            VALID_BODY.replace(items[0] + "\n" + items[1], items[1] + "\n" + items[0]),
        ]
        for body in variants:
            self.assertIn("Checklist must preserve every template item in its original order.", validate_body(body))

    def test_comment_cannot_supply_a_review_section(self) -> None:
        """Treat a review section hidden in an HTML comment as missing."""
        body = VALID_BODY.replace("## Review and closeout", "<!--\n## Review and closeout") + "\n-->"
        self.assertTrue(validate_body(body))

    def test_checked_in_template_shape(self) -> None:
        """Accept the repository template as a valid unfilled contract."""
        with open(".github/PULL_REQUEST_TEMPLATE.md", encoding="utf-8") as template:
            self.assertEqual(validate_template(template.read()), [])

    def test_complete_body_passes(self) -> None:
        """Accept a complete body with explicit validation and review outcomes."""
        self.assertEqual(validate_body(VALID_BODY), [])

    def test_html_comments_do_not_fill_blank_fields(self) -> None:
        """Reject a blank release field even when guidance follows in a comment."""
        body = VALID_BODY.replace(
            "- Completion condition: The template shape and filled-body validator pass locally.",
            "- Completion condition:\n\n<!-- guidance must not count -->",
        )
        self.assertIn(
            "Replace release boundary field placeholder: Completion condition",
            validate_body(body),
        )

    def test_indented_multiline_field_is_populated(self) -> None:
        """Accept verification steps supplied as an indented multiline list."""
        body = VALID_BODY.replace(
            "- Verification steps: python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md.",
            "- Verification steps:\n  1. Run the local validator.\n  2. Inspect the result.",
        )
        self.assertEqual(validate_body(body), [])

    def test_field_label_must_follow_bullet_on_same_line(self) -> None:
        body = VALID_BODY.replace(
            "- Problem: Maintainers need a consistent, evidence-led PR body.",
            "-\nProblem: Maintainers need a consistent, evidence-led PR body.",
        )
        self.assertIn("Missing required summary field: Problem", validate_body(body))

    def test_required_not_applicable_field_needs_reason(self) -> None:
        """Reject a required field marked n.a. without an explanation."""
        body = VALID_BODY.replace(
            "- Risk and rollback: Revert the template and script together.",
            "- Risk and rollback: n.a.",
        )
        self.assertTrue(any("needs a reason for n.a." in error for error in validate_body(body)))

    def test_empty_blocked_command_reason_fails(self) -> None:
        """Reject blocked command reasons that are empty or whitespace only."""
        command = "- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> pass"
        for reason in ["", "   "]:
            with self.subTest(reason=reason):
                body = VALID_BODY.replace(command, command.replace("-> pass", f"-> blocked ({reason})"))
                self.assertTrue(any("Command evidence must use" in error for error in validate_body(body)))

    def test_documented_command_outcomes_are_accepted(self) -> None:
        """Bind every outcome alternative to the required command-line prefix."""
        command = "- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> pass"
        for outcome in [
            "pass",
            "pass (local check).",
            "fail",
            "fail (known failure).",
            "n.a. (not provided by this repository)",
            "n/a (not applicable)",
            "blocked (service unavailable)",
        ]:
            with self.subTest(outcome=outcome):
                body = VALID_BODY.replace(command, command.replace("-> pass", f"-> {outcome}"))
                self.assertEqual(validate_body(body), [])

    def test_outcome_alternatives_do_not_admit_unstructured_lines(self) -> None:
        """Do not accept missing command identity or unknown outcomes."""
        command = "- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> pass"
        for replacement in ["- Command: -> pass", "- Command: `check` -> success", "- Command: `check` -> blocked"]:
            with self.subTest(replacement=replacement):
                self.assertTrue(validate_body(VALID_BODY.replace(command, replacement)))

    def test_template_requires_fixed_checklist_items(self) -> None:
        """Reject a template that omits a required checklist item."""
        template = Path(".github/PULL_REQUEST_TEMPLATE.md").read_text(encoding="utf-8")
        removed = template.replace(
            "- [ ] Merge is blocked until all required checks pass.\n", ""
        )
        self.assertTrue(any("checklist" in error.lower() for error in validate_template(removed)))

    def test_release_mode_must_be_concrete(self) -> None:
        """Reject the unfilled release-mode options from the template."""
        body = VALID_BODY.replace(
            "- Release mode: Harness",
            "- Release mode: Prototype / Portfolio / Product / Harness / n.a. because reason",
        )
        self.assertIn(
            "Release mode must be Prototype, Portfolio, Product, Harness, or `n.a. because <reason>`." ,
            validate_body(body),
        )

    def test_command_evidence_requires_blocked_reason(self) -> None:
        """Reject a blocked command outcome with no reason attached."""
        body = VALID_BODY.replace(
            "- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> pass",
            "- Command: `python3 script/validate_pr_template.py --template .github/PULL_REQUEST_TEMPLATE.md` -> blocked",
        )
        self.assertTrue(any("Command evidence must use" in error for error in validate_body(body)))

    def test_linked_issue_acceptance_trace_is_issue_bound(self) -> None:
        """Accept an issue reference tied to a concrete acceptance ID and evidence."""
        body = VALID_BODY.replace(
            "- Plan IDs: n.a. because no external plan is linked.",
            "- Plan IDs: JSC-123",
        ).replace(
            "- Linear reference: n.a. because no Linear issue is linked.",
            "- Linear reference: Refs JSC-123",
        ).replace(
            "- Acceptance trace: n.a. because no external acceptance IDs apply.",
            "- Acceptance trace: JSC-123 AC-123-001 -> script/validate_pr_template.py",
        ).replace(
            "- Linked issue relationship: n.a. because no issue is linked.",
            "- Linked issue relationship: implementation closure; completed acceptance IDs: AC-123-001.",
        )
        self.assertEqual(validate_body(body), [])

    def test_local_absolute_paths_are_not_portable_evidence(self) -> None:
        """Reject evidence that depends on a workstation-specific absolute path."""
        body = VALID_BODY.replace(
            "- Evidence after fix: The validator returned a passing result for the checked-in template.",
            "- Evidence after fix: /Users/example/skillsbar/result.json.",
        )
        self.assertIn(
            "PR body must not include local absolute paths; use repo-relative evidence references.",
            validate_body(body),
        )


if __name__ == "__main__":
    unittest.main()
