import array
import tempfile
from pathlib import Path
import unittest

import deck_voice_e2e as check


class DeckVoiceE2ETests(unittest.TestCase):
    def test_pcm_stats(self):
        samples = array.array("h", [0, 100, -100, 200, -200])
        rms, peak = check.pcm_stats(samples.tobytes())
        self.assertGreater(rms, 140)
        self.assertLess(rms, 142)
        self.assertEqual(200, peak)

    def test_failed_status_preserves_last_success(self):
        status = check.build_status(
            {"last_success": 1234.5},
            success=False,
            now=2000,
            duration=4.2,
            stage="stt",
            detail="no transcript",
            completed={"microphone", "wake_word"},
        )
        self.assertFalse(status["success"])
        self.assertEqual(1234.5, status["last_success"])
        self.assertEqual(["microphone", "wake_word"], status["completed_stages"])

    def test_success_updates_last_success(self):
        status = check.build_status(
            {},
            success=True,
            now=3000.25,
            duration=9,
            stage="complete",
            detail="ok",
            completed=set(check.STAGES),
        )
        self.assertEqual(3000.25, status["last_success"])
        self.assertEqual(list(check.STAGES), status["completed_stages"])

    def test_metrics_have_bounded_stage_labels(self):
        status = check.build_status(
            {},
            success=False,
            now=10,
            duration=2,
            stage="conversation",
            detail="failed",
            completed={"microphone", "wake_word", "stt"},
        )
        metrics = check.render_metrics(status)
        self.assertIn("thorn_deck_voice_e2e_success 0", metrics)
        self.assertIn('stage="stt"} 1', metrics)
        self.assertIn('stage="conversation"} 0', metrics)
        self.assertEqual(len(check.STAGES), metrics.count("thorn_deck_voice_e2e_stage_success{"))

    def test_atomic_status_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "status.json"
            check.atomic_json(path, {"success": True})
            self.assertEqual({"success": True}, check.load_json(path))
            self.assertEqual(0o644, path.stat().st_mode & 0o777)


if __name__ == "__main__":
    unittest.main()
