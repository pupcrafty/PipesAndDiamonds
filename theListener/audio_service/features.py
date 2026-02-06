from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

import numpy as np


def clamp(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def lerp(old: float, new: float, alpha: float) -> float:
    return (1.0 - alpha) * old + alpha * new


@dataclass
class FeatureConfig:
    bass_lo: float = 40.0
    bass_hi: float = 160.0
    mid_lo: float = 160.0
    mid_hi: float = 1200.0
    treble_lo: float = 1200.0
    treble_hi: float = 8000.0
    gain: float = 1.5
    smooth: float = 0.25
    auto_normalize: bool = True
    loudness_smooth: float = 0.08
    target_level: float = 0.08
    min_norm: float = 0.25
    max_norm: float = 8.0
    silence_gate: float = 0.0006
    noise_floor: float = 0.002
    noise_floor_ratio_of_target: float = 0.04
    beat_flux_thresh: float = 0.010
    beat_refractory: float = 0.22
    pulse_flux_thresh: float = 0.016
    pulse_refractory: float = 0.08
    movement_smooth: float = 0.10


class FeatureExtractor:
    def __init__(self, sample_rate: int, win_size: int, hop_size: int, config: FeatureConfig):
        self.sample_rate = sample_rate
        self.win_size = win_size
        self.hop_size = hop_size
        self.config = config
        self._window = np.hanning(win_size).astype(np.float32)
        self._buffer = np.zeros(win_size, dtype=np.float32)
        self._freqs = np.fft.rfftfreq(win_size, 1.0 / sample_rate)
        self._beat_cd = 0.0
        self._pulse_cd = 0.0
        self._b_s = 0.0
        self._m_s = 0.0
        self._t_s = 0.0
        self._b_prev = 0.0
        self._t_prev = 0.0
        self._energy_s = 0.0
        self._movement_s = 0.0
        self._loudness_ema = 0.0
        self._energy_var_ema = 0.0

    def process(self, samples: np.ndarray) -> Dict[str, float | bool]:
        if samples.size == 0:
            return {}
        if samples.size > self.win_size:
            samples = samples[-self.win_size :]
        shift = samples.size
        self._buffer = np.roll(self._buffer, -shift)
        self._buffer[-shift:] = samples
        windowed = self._buffer * self._window
        spectrum = np.fft.rfft(windowed)
        magnitude = np.abs(spectrum)

        b_raw = self._band_energy(magnitude, self.config.bass_lo, self.config.bass_hi)
        m_raw = self._band_energy(magnitude, self.config.mid_lo, self.config.mid_hi)
        t_raw = self._band_energy(magnitude, self.config.treble_lo, self.config.treble_hi)
        energy_raw = b_raw + m_raw + t_raw

        self._loudness_ema = lerp(self._loudness_ema, energy_raw, self.config.loudness_smooth)

        norm = 1.0
        if self.config.auto_normalize:
            if self._loudness_ema <= self.config.silence_gate:
                norm = 0.0
            else:
                norm = self.config.target_level / max(self._loudness_ema, 1e-6)
                norm = clamp(norm, self.config.min_norm, self.config.max_norm)

        b = b_raw * self.config.gain * norm
        m = m_raw * self.config.gain * norm
        t = t_raw * self.config.gain * norm

        adaptive_floor = max(self.config.noise_floor, self.config.target_level * self.config.noise_floor_ratio_of_target)
        if b < adaptive_floor:
            b = 0.0
        if m < adaptive_floor:
            m = 0.0
        if t < adaptive_floor:
            t = 0.0

        self._b_s = lerp(self._b_s, b, self.config.smooth)
        self._m_s = lerp(self._m_s, m, self.config.smooth)
        self._t_s = lerp(self._t_s, t, self.config.smooth)

        bass_flux = max(self._b_s - self._b_prev, 0.0)
        treble_flux = max(self._t_s - self._t_prev, 0.0)
        self._b_prev = self._b_s
        self._t_prev = self._t_s

        dt = self.hop_size / float(self.sample_rate)
        self._beat_cd = max(self._beat_cd - dt, 0.0)
        self._pulse_cd = max(self._pulse_cd - dt, 0.0)

        beat = False
        if self._beat_cd <= 0.0 and bass_flux >= self.config.beat_flux_thresh:
            beat = True
            self._beat_cd = self.config.beat_refractory

        pulse = False
        if self._pulse_cd <= 0.0 and treble_flux >= self.config.pulse_flux_thresh:
            pulse = True
            self._pulse_cd = self.config.pulse_refractory

        energy = self._b_s + self._m_s + self._t_s
        prev_energy = self._energy_s
        self._energy_s = lerp(self._energy_s, energy, self.config.movement_smooth)
        movement = self._energy_s - prev_energy
        self._movement_s = lerp(self._movement_s, movement, 0.35)

        energy_dev = energy - self._energy_s
        self._energy_var_ema = lerp(self._energy_var_ema, energy_dev * energy_dev, 0.15)

        total_energy = self._b_s + self._m_s + self._t_s
        total_safe = max(total_energy, 1e-6)
        bass_ratio = self._b_s / total_safe
        mid_ratio = self._m_s / total_safe
        treble_ratio = self._t_s / total_safe
        energy_delta = total_energy - prev_energy
        mean_band = total_energy / 3.0
        band_variance = ((self._b_s - mean_band) ** 2 + (self._m_s - mean_band) ** 2 + (self._t_s - mean_band) ** 2) / 3.0
        band_balance = 1.0 - clamp(band_variance / max(total_energy * total_energy, 1e-6), 0.0, 1.0)

        return {
            "bass": self._b_s,
            "mid": self._m_s,
            "treble": self._t_s,
            "total_energy": total_energy,
            "energy_delta": energy_delta,
            "movement": self._movement_s,
            "energy_variance": self._energy_var_ema,
            "bass_ratio": bass_ratio,
            "mid_ratio": mid_ratio,
            "treble_ratio": treble_ratio,
            "band_balance": band_balance,
            "beat": beat,
            "pulse": pulse,
        }

    def _band_energy(self, magnitude: np.ndarray, lo_hz: float, hi_hz: float) -> float:
        mask = (self._freqs >= lo_hz) & (self._freqs < hi_hz)
        if not np.any(mask):
            return 0.0
        return float(np.sum(magnitude[mask]))
