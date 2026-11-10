"""Exercise bootstrap scripts against disposable state and mocked applications."""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("secrets", "credentials", "seed", "workflows", "mock/bin"):
            (self.root / name).mkdir(parents=True)
        self.env = dict(os.environ, MOCK_ROOT=str(self.root))
        self.mock("psql", """
command = next((arg for arg in sys.argv if arg.startswith('--command=')), '')
if 'user_api_keys' in command:
    print(os.environ.get('MOCK_TOKEN', 'header.payload.signature'))
elif 'workflow_entity' in command:
    print(os.environ.get('MOCK_WORKFLOW_EXISTS', '0'))
elif 'count(*)' in command:
    print(os.environ.get('MOCK_OWNER_COUNT', '1'))
else:
    with open(os.path.join(os.environ['MOCK_ROOT'], 'sql.log'), 'a') as log:
        log.write(command + '\\n')
""")
        self.mock("n8n", """
with open(os.path.join(os.environ['MOCK_ROOT'], 'n8n.log'), 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
sys.exit(int(os.environ.get('MOCK_N8N_EXIT', '0')))
""")
        for name in ("fleet-health.json", "maintenance.json", "nascar-scores.json"):
            (self.root / "workflows" / name).write_text("{}")

    def mock(self, name, body):
        path = self.root / "mock/bin" / name
        path.write_text(f"#!{sys.executable}\nimport os, sys, json\n{body}")
        path.chmod(0o755)

    def run_script(self, name, **env):
        values = {
            "bash": shutil.which("bash"),
            "coreutils": os.environ["LOOM_TEST_COREUTILS"],
            "openssl": os.environ["LOOM_TEST_OPENSSL"],
            "diffutils": os.environ["LOOM_TEST_DIFFUTILS"],
            "postgresql": str(self.root / "mock"),
            "n8n": str(self.root / "mock"),
            "secretStateDirectory": str(self.root / "secrets"),
            "modelCredentialDirectory": str(self.root / "credentials"),
            "seedStateDirectory": str(self.root / "seed"),
            "starterWorkflowDirectory": str(self.root / "workflows"),
            "espnWorkflow": str(self.root / "espn.json"),
            "workflowIds": "'allowed-workflow'",
        }
        template = (Path(__file__).parent / name).read_text()
        rendered = re.sub(r"@([A-Za-z][A-Za-z0-9]*)@", lambda match: values[match[1]], template)
        script = self.root / name
        script.write_text(rendered)
        return subprocess.run(
            [shutil.which("bash"), str(script)],
            env=self.env | env,
            text=True,
            capture_output=True,
            check=False,
        )

    def calls(self):
        path = self.root / "n8n.log"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_secrets_are_private_stable_and_newline_free(self):
        result = self.run_script("create-secrets.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        original = {}
        for name in ("encryption-key", "runner-auth-token"):
            path = self.root / "secrets" / name
            original[name] = path.read_bytes(), path.stat().st_mtime_ns
            self.assertRegex(path.read_text(), r"\A[0-9a-f]{64}\Z")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o400)
        self.assertEqual(self.run_script("create-secrets.sh").returncode, 0)
        for name, (value, modified) in original.items():
            path = self.root / "secrets" / name
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), (value, modified))

    def test_legacy_newline_normalization_does_not_rotate_key(self):
        path = self.root / "secrets/encryption-key"
        path.write_text("a" * 64 + "\r\n")
        result = self.run_script("create-secrets.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), "a" * 64)

    def test_malformed_existing_key_is_not_overwritten(self):
        path = self.root / "secrets/encryption-key"
        path.write_text("do-not-replace")
        self.assertNotEqual(self.run_script("create-secrets.sh").returncode, 0)
        self.assertEqual(path.read_text(), "do-not-replace")

    def test_staged_token_is_private_and_invalid_rotation_preserves_it(self):
        result = self.run_script("stage-mcp-token.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        path = self.root / "credentials/n8n-mcp-token"
        self.assertEqual(path.read_text(), "header.payload.signature")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o400)
        self.assertNotIn(path.read_text(), result.stdout + result.stderr)
        result = self.run_script("stage-mcp-token.sh", MOCK_TOKEN="invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), "header.payload.signature")

    def test_owner_setup_defers_every_import(self):
        result = self.run_script("seed-workflows.sh", MOCK_OWNER_COUNT="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(list((self.root / "seed").iterdir()), [])

    def test_seed_is_idempotent_and_publishes_only_named_workflows(self):
        result = self.run_script("seed-workflows.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(sum(call[0] == "import:workflow" for call in calls), 4)
        self.assertEqual(
            [call[1] for call in calls if call[0] == "publish:workflow"],
            ["--id=6ZtXlBrFI0nGZ5R2", "--id=CasitaEspnSports"],
        )
        self.assertEqual(self.run_script("seed-workflows.sh").returncode, 0)
        self.assertEqual(self.calls(), calls)

    def test_failed_import_does_not_mark_success(self):
        result = self.run_script("seed-workflows.sh", MOCK_N8N_EXIT="7")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(list((self.root / "seed").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
