"""Bounded regressions for malformed PR text through the real parser."""

import subprocess
import sys
import unittest
from pathlib import Path

from validate_pr_template import normalize, strip_comments, validate_body
from test_validate_pr_template import VALID_BODY


class ParserSecurityTests(unittest.TestCase):
    def test_unterminated_delimiters_finish_within_budget(self):
        for expression in (
            "strip_comments('<!--' + ' ' * 20000)",
            "normalize('```' + ' ' * 20000 + 'x')",
        ):
            with self.subTest(expression=expression):
                subprocess.run(
                    [sys.executable, '-c',
                     'from validate_pr_template import strip_comments, normalize; ' + expression],
                    cwd=Path(__file__).parent, timeout=3, check=True,
                    capture_output=True,
                )

    def test_comment_and_fence_semantics(self):
        self.assertEqual(strip_comments('a<!-- x -->b<!--y-->c'), 'abc')
        self.assertEqual(strip_comments('a<!-- unfinished'), 'a<!-- unfinished')
        self.assertEqual(normalize('```python\n hello world \n```'), 'hello world')
        self.assertEqual(normalize('```\n```'), '')
        self.assertEqual(normalize('` hello `'), 'hello')
        self.assertEqual(normalize('```python\nunfinished'), '```python unfinished')

    def test_longer_closing_fence_cannot_populate_required_field(self):
        """Reject empty fenced values even when the closing fence is longer."""
        for fence in ('```\n````', '```python\n`````', '````\n````', '`````python\n``````'):
            with self.subTest(fence=fence):
                self.assertEqual(normalize(fence), '')
                body = VALID_BODY.replace(
                    '- Problem: Maintainers need a consistent, evidence-led PR body.',
                    '- Problem: ' + fence,
                )
                self.assertTrue(validate_body(body))
        self.assertEqual(normalize('```python\n substantive evidence \n````'), 'substantive evidence')
        self.assertEqual(normalize('````python\n substantive evidence \n`````'), 'substantive evidence')
        self.assertEqual(normalize('````python\nunfinished\n```'), '````python unfinished ```')


if __name__ == '__main__':
    unittest.main()
