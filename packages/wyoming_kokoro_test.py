"""Regression tests for Kokoro speech normalization and stream routing."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).with_name("wyoming-kokoro.py")
SPEC = importlib.util.spec_from_file_location("wyoming_kokoro", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
KOKORO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(KOKORO)


class SpeechTests(unittest.TestCase):
    def test_normalizes_screen_text(self) -> None:
        self.assertEqual(
            KOKORO.normalize_for_speech("**SOC** is at 72°F"),
            "S O C is at 72 degrees Fahrenheit",
        )

    def test_short_acknowledgement_waits_then_uses_fast_voice(self) -> None:
        selector = KOKORO.StreamingVoiceSelector()
        self.assertEqual(selector.add("Okay, turning it off."), (None, ""))
        self.assertEqual(
            selector.finish(),
            ("fast", "Okay, turning it off."),
        )

    def test_normal_reply_streams_naturally_without_waiting(self) -> None:
        selector = KOKORO.StreamingVoiceSelector()
        self.assertEqual(
            selector.add("The weather is clear today."),
            ("natural", "The weather is clear today."),
        )

    def test_long_acknowledgement_stays_on_one_natural_engine(self) -> None:
        selector = KOKORO.StreamingVoiceSelector()
        self.assertEqual(selector.add("Okay."), (None, ""))
        mode, text = selector.add(
            "I found enough detail that this longer response should use the natural voice "
            "instead of the quick acknowledgement voice."
        )
        self.assertEqual(mode, "natural")
        self.assertEqual(
            text,
            "Okay. I found enough detail that this longer response should use the natural "
            "voice instead of the quick acknowledgement voice.",
        )
        self.assertEqual(
            selector.finish("It remains natural."),
            ("natural", "It remains natural."),
        )


if __name__ == "__main__":
    unittest.main()
