from __future__ import annotations

import json
from typing import Dict

from pythonosc.udp_client import SimpleUDPClient


class OscOut:
    def __init__(self, host: str, port: int):
        self.client = SimpleUDPClient(host, port)

    def send_clock_state(self, bpm: float, confidence: float, beat_id: int, now: float) -> None:
        self.client.send_message("/clock/bpm", float(bpm))
        self.client.send_message("/clock/conf", float(confidence))
        self.client.send_message("/clock/beat_id", int(beat_id))
        self.client.send_message("/clock/time", float(now))

    def send_clock_beat(self, beat_id: int) -> None:
        self.client.send_message("/clock/beat", int(beat_id))

    def send_audio_payload(self, payload: Dict[str, float | bool]) -> None:
        self.client.send_message("/audio/standardized", json.dumps(payload))
        for key in [
            "bass",
            "mid",
            "treble",
            "beat",
            "pulse",
            "movement",
            "total_energy",
            "energy_delta",
            "energy_variance",
            "bass_ratio",
            "mid_ratio",
            "treble_ratio",
            "band_balance",
        ]:
            if key not in payload:
                continue
            value = payload[key]
            if isinstance(value, bool):
                value = 1 if value else 0
            self.client.send_message(f"/audio/{key}", value)

    def send_phrase(self, phrase: str) -> None:
        self.client.send_message("/phrase/current", phrase)
