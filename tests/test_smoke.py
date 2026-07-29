"""
Smoke tests for the Spatial Transcriptomics Analysis pipeline.

These verify the pipeline installs correctly and each script's CLI is
well-formed, without requiring the full (multi-hundred-MB) GEF dataset.

If a real (ideally small/subsampled) GEF file is available, point
$ST_TEST_GEF at it to additionally run the baseline pipeline end-to-end
and confirm it produces output. This is skipped by default / in CI
unless that variable is set.

Run with:
    python -m unittest tests/test_smoke.py -v
"""
import importlib
import os
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI_SCRIPTS = ["baseline.py", "ensemble_clustering.py", "annotator.py", "ai_agent.py"]

if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)


class TestImports(unittest.TestCase):
    """Each module should import cleanly (no errors, no required GEF file at import time)."""

    def test_modules_import(self):
        for module_name in [
            "ovarian_knowledge_base",
            "baseline",
            "annotator",
            "ensemble_clustering",
            "ai_agent",
        ]:
            with self.subTest(module=module_name):
                importlib.import_module(module_name)


class TestCLI(unittest.TestCase):
    """Every pipeline script should expose a working --help CLI (no source editing required to run)."""

    def test_help_exits_cleanly_with_input_output_flags(self):
        for script in CLI_SCRIPTS:
            with self.subTest(script=script):
                result = subprocess.run(
                    [sys.executable, os.path.join(REPO_ROOT, script), "--help"],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, msg=result.stderr)
                self.assertIn("--input", result.stdout)
                self.assertIn("--output", result.stdout)


@unittest.skipUnless(
    os.environ.get("ST_TEST_GEF"),
    "Set $ST_TEST_GEF to a sample .gef file to run the end-to-end smoke test",
)
class TestEndToEndBaseline(unittest.TestCase):
    """Runs the baseline pipeline against a real GEF file end-to-end and checks it produces output."""

    def test_baseline_runs_and_produces_output(self):
        gef_path = os.environ["ST_TEST_GEF"]
        with tempfile.TemporaryDirectory() as out_dir:
            result = subprocess.run(
                [
                    sys.executable,
                    os.path.join(REPO_ROOT, "baseline.py"),
                    "--input", gef_path,
                    "--output", out_dir,
                ],
                capture_output=True,
                text=True,
                timeout=1800,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            produced = os.listdir(out_dir)
            self.assertTrue(produced, "baseline.py produced no output files")


if __name__ == "__main__":
    unittest.main()
