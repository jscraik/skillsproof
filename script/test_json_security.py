"""Compile the real JSON getter and bound hostile inputs in child processes."""

import subprocess
import tempfile
import unittest
from pathlib import Path


class JSONSecurityTests(unittest.TestCase):
    def test_hostile_output_finishes_within_budget(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory(prefix='skillsproof-json-') as scratch:
            scratch = Path(scratch)
            main = scratch / 'main.swift'
            main.write_text('''import Foundation
let braces = String(repeating: "{", count: 30000)
let input = CommandLine.arguments[1] == "valid"
    ? "{\\"text\\":\\"" + braces + "\\"}" : braces
let result = CommandResult(exitCode: 0, stdout: input, stderr: "").json
precondition((result != nil) == (CommandLine.arguments[1] == "valid"))
print("bounded JSON parsing passed")
''')
            binary = scratch / 'probe'
            subprocess.run(['swiftc', '-module-cache-path', str(scratch / 'cache'),
                            str(root / 'Sources/SkillsBarCore/Shell.swift'), str(main),
                            '-o', str(binary)], check=True, timeout=60, capture_output=True)
            for mode in ('valid', 'unmatched'):
                with self.subTest(mode=mode):
                    subprocess.run([str(binary), mode], timeout=3, check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
