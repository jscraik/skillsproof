#!/usr/bin/env python3
"""Check a packaged release, including hostile fixture environment overrides."""
import os
from pathlib import Path
import subprocess
import sys


def main():
    bundle = Path(sys.argv[1]).resolve()
    binary = bundle / "Contents/MacOS/SkillsProof"
    forbidden = [b"/Users/", b"SKILLSBAR_DEMO_MODE", b"SKILLSBAR_REVIEW_FIXTURE", b"TESSL_REGISTRY_FIXTURE"]
    for path in bundle.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            if any(value in data for value in forbidden):
                raise SystemExit(f"Release contains a personal path or fixture switch: {path.relative_to(bundle)}")
    environment = dict(os.environ)
    environment.update(SKILLSBAR_DEMO_MODE="1", SKILLSBAR_REVIEW_FIXTURE="reference",
                       TESSL_REGISTRY_FIXTURE="1", TESSL_REGISTRY_FIXTURE_SCORE="100")
    subprocess.run([str(binary), "--check-release-safety", "--snapshot", "/dev/null"],
                   env=environment, check=True, timeout=30)


if __name__ == "__main__":
    main()
