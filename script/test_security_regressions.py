"""Bounded regressions for malformed PR text through the real parser."""

import subprocess
import sys
import unittest
from pathlib import Path

from validate_pr_template import normalize, strip_comments


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


if __name__ == '__main__':
    unittest.main()
