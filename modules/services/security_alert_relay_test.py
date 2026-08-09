import hashlib
import hmac
import tempfile
import unittest
from pathlib import Path

import security_alert_relay as relay


class RelayPureFunctionTests(unittest.TestCase):
    def alert(self):
        return {
            "status": "firing",
            "fingerprint": "1234abcd",
            "startsAt": "2026-08-09T12:00:00Z",
            "generatorURL": "https://soc.guildedthorn.arpa/alerting/grafana/example/view",
            "labels": {
                "alertname": "OpenCanary decoy service touched",
                "category": "security",
                "severity": "critical",
                "src_host": "203.0.113.40",
            },
            "annotations": {
                "summary": "Connection from 203.0.113.40 to bad.example:443; https://bad.example/a",
                "hash": "a" * 64,
            },
        }

    def test_only_firing_critical_security_alerts_route(self):
        alert = self.alert()
        self.assertTrue(relay.should_route(alert))
        alert["status"] = "resolved"
        self.assertFalse(relay.should_route(alert))
        alert["status"] = "firing"
        alert["labels"]["category"] = "pipeline"
        self.assertFalse(relay.should_route(alert))

    def test_observable_extraction_is_typed_and_deduplicated(self):
        observables = set(relay.extract_observables(self.alert()))
        self.assertIn(relay.Observable("ip", "203.0.113.40"), observables)
        self.assertIn(relay.Observable("domain", "bad.example"), observables)
        self.assertIn(relay.Observable("url", "https://bad.example/a"), observables)
        self.assertIn(relay.Observable("hash", "a" * 64), observables)

    def test_source_reference_is_stable(self):
        self.assertEqual(relay.source_reference(self.alert()), "grafana:1234abcd")

    def test_thehive_payload_preserves_context(self):
        alert = self.alert()
        observables = relay.extract_observables(alert)
        payload = relay.build_thehive_payload(
            alert,
            observables,
            [
                {
                    "value": "bad.example",
                    "entity_type": "Domain-Name",
                    "score": 80,
                    "description": "ThreatFox IOC",
                    "creators": ["Abuse.ch"],
                    "labels": ["malware"],
                    "references": ["https://threatfox.abuse.ch/"],
                }
            ],
            None,
        )
        self.assertEqual(payload["sourceRef"], "grafana:1234abcd")
        self.assertEqual(payload["severity"], 4)
        self.assertIn("OpenCTI enrichment", payload["description"])
        self.assertEqual(payload["externalLink"], alert["generatorURL"])

    def test_state_survives_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            state = relay.StateStore(path)
            state.remember("grafana:one", "~123")
            self.assertTrue(relay.StateStore(path).contains("grafana:one"))

    def test_hmac_rejects_tampering_and_replay(self):
        body = b'{"status":"firing"}'
        secret = b"test-only-secret"
        timestamp = "1786291200"
        signature = hmac.new(
            secret,
            timestamp.encode() + b":" + body,
            hashlib.sha256,
        ).hexdigest()
        self.assertTrue(
            relay.valid_hmac(body, secret, signature, timestamp, now=1786291201)
        )
        self.assertFalse(
            relay.valid_hmac(b"tampered", secret, signature, timestamp, now=1786291201)
        )
        self.assertFalse(
            relay.valid_hmac(body, secret, signature, timestamp, now=1786291801)
        )


if __name__ == "__main__":
    unittest.main()
