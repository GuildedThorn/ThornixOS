"""Check lifecycle arguments and lock handling without a Docker daemon."""

import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ComposeLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.log = Path(self.temporary.name) / "arguments"
        self.env = dict(os.environ, COMPOSE_TEST_LOG=str(self.log))

    def run_script(self, name):
        return subprocess.run(
            [os.environ[name]], env=self.env, capture_output=True, check=False
        )

    def arguments(self):
        return self.log.read_bytes().decode().rstrip("\0").split("\0")

    def test_start_preserves_project_argument_and_keeps_volumes(self):
        result = self.run_script("START_SCRIPT")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments(), [
            "--project-name", "project with spaces", "--file", os.environ["COMPOSE_FILE"],
            "up", "--detach", "--remove-orphans",
        ])

    def test_stop_uses_stop_rather_than_down(self):
        result = self.run_script("STOP_SCRIPT")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments()[-3:], ["stop", "--timeout", "90"])

    def test_start_does_not_run_compose_while_another_action_holds_lock(self):
        with open("/tmp/thornix-compose-test.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_script("START_SCRIPT")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_admin_command_requires_root_before_contacting_compose(self):
        if os.geteuid() == 0:
            self.skipTest("requires the ordinary unprivileged Nix build user")
        result = self.run_script("ADMIN_SCRIPT")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"must run as root", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
