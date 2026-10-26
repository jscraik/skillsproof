"""Rejection checks for accidental release content; no live app is launched."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ReleaseArtifactTests(unittest.TestCase):
    def test_rejects_personal_paths_and_fixture_switches(self):
        checker = Path(__file__).with_name("check_release.py")
        for content in (b"/Users/example/source", b"TESSL_REGISTRY_FIXTURE_SCORE",
                        b"SKILLSBAR_DEMO_MODE", b"SKILLSBAR_REVIEW_FIXTURE"):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                bundle = Path(directory) / "SkillsProof.app"
                resources = bundle / "Contents/Resources"
                resources.mkdir(parents=True)
                (resources / "accidental.txt").write_bytes(content)
                result = subprocess.run([sys.executable, str(checker), str(bundle)],
                                        capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("personal path or fixture switch", result.stderr)


if __name__ == "__main__":
    unittest.main()
