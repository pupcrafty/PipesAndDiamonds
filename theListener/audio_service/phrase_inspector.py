from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional


def clamp(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def lerp(old: float, new: float, alpha: float) -> float:
    return (1.0 - alpha) * old + alpha * new


@dataclass
class PhraseInspector:
    state_silence: str = "SILENCE / VOID"
    state_build: str = "BUILD"
    state_fill: str = "FILL"
    state_impact: str = "IMPACT / HIT"
    state_drop: str = "DROP"
    state_groove: str = "GROOVE"
    state_breakdown: str = "BREAKDOWN"
    state_switchup: str = "SWITCHUP / GENRE FLIP"

    energy_smooth: float = 0.12
    trend_smooth: float = 0.18
    beat_smooth: float = 0.2
    ratio_long_smooth: float = 0.02

    silence_threshold: float = 0.01
    low_energy_threshold: float = 0.04
    high_energy_threshold: float = 0.14

    build_slope_threshold: float = 0.002
    outro_slope_threshold: float = -0.002

    impact_energy_delta_threshold: float = 0.04
    drop_energy_delta_threshold: float = 0.02
    centroid_drop_threshold: float = 0.035

    beat_stable_threshold: float = 0.6
    beat_unstable_threshold: float = 0.25
    pulse_dense_threshold: float = 0.55
    pulse_sparse_threshold: float = 0.2

    bass_ratio_high: float = 0.45
    bass_ratio_low: float = 0.2
    treble_ratio_high: float = 0.45
    mid_ratio_focus: float = 0.45

    variance_high_threshold: float = 0.35
    variance_low_threshold: float = 0.12
    bridge_shift_threshold: float = 0.22

    enter_threshold: float = 0.55
    weak_score_threshold: float = 0.35
    drop_override_threshold: float = 0.9
    impact_trigger_threshold: float = 0.7
    fallback_weak_beats: int = 3
    drop_confirm_beats: int = 4
    build_confirm_beats: int = 4
    switchup_confirm_beats: int = 8

    _current_state: str = field(default="SILENCE / VOID", init=False)
    _beat_index: int = field(default=0, init=False)
    _phrase_enter_beat: int = field(default=0, init=False)
    _impact_return_state: str = field(default="", init=False)
    _beat_confidence: float = field(default=0.0, init=False)
    _osc_beat_seen: bool = field(default=False, init=False)
    _drop_run_beats: int = field(default=0, init=False)
    _build_run_beats: int = field(default=0, init=False)
    _switchup_run_beats: int = field(default=0, init=False)
    _weak_score_beats: int = field(default=0, init=False)
    _last_scores: Dict[str, float] = field(default_factory=dict, init=False)

    _energy_ema: float = field(default=0.0, init=False)
    _movement_ema: float = field(default=0.0, init=False)
    _variance_ema: float = field(default=0.0, init=False)
    _beat_ema: float = field(default=0.0, init=False)
    _pulse_ema: float = field(default=0.0, init=False)

    _bass_ratio_ema: float = field(default=0.0, init=False)
    _mid_ratio_ema: float = field(default=0.0, init=False)
    _treble_ratio_ema: float = field(default=0.0, init=False)

    _bass_ratio_long: float = field(default=0.0, init=False)
    _mid_ratio_long: float = field(default=0.0, init=False)
    _treble_ratio_long: float = field(default=0.0, init=False)

    _last_bass_energy: float = field(default=0.0, init=False)
    _centroid_proxy: float = field(default=0.0, init=False)
    _last_centroid_proxy: float = field(default=0.0, init=False)

    def update(self, payload: Dict[str, float | bool], beat_confidence: float, osc_beat: bool) -> Optional[str]:
        if "total_energy" not in payload:
            return None

        total_energy = float(payload["total_energy"])
        movement = float(payload.get("movement", 0.0))
        variance = float(payload.get("energy_variance", 0.0))
        beat = bool(payload.get("beat", False))
        pulse = bool(payload.get("pulse", False))
        bass_ratio = float(payload.get("bass_ratio", 0.0))
        mid_ratio = float(payload.get("mid_ratio", 0.0))
        treble_ratio = float(payload.get("treble_ratio", 0.0))

        rolling_energy = self._energy_ema
        self._energy_ema = lerp(self._energy_ema, total_energy, self.energy_smooth)
        self._movement_ema = lerp(self._movement_ema, movement, self.trend_smooth)
        self._variance_ema = lerp(self._variance_ema, variance, self.trend_smooth)
        self._beat_ema = lerp(self._beat_ema, 1.0 if beat else 0.0, self.beat_smooth)
        self._pulse_ema = lerp(self._pulse_ema, 1.0 if pulse else 0.0, self.beat_smooth)

        self._bass_ratio_ema = lerp(self._bass_ratio_ema, bass_ratio, self.energy_smooth)
        self._mid_ratio_ema = lerp(self._mid_ratio_ema, mid_ratio, self.energy_smooth)
        self._treble_ratio_ema = lerp(self._treble_ratio_ema, treble_ratio, self.energy_smooth)

        self._bass_ratio_long = lerp(self._bass_ratio_long, bass_ratio, self.ratio_long_smooth)
        self._mid_ratio_long = lerp(self._mid_ratio_long, mid_ratio, self.ratio_long_smooth)
        self._treble_ratio_long = lerp(self._treble_ratio_long, treble_ratio, self.ratio_long_smooth)

        bass_energy = total_energy * bass_ratio
        bass_energy_delta = bass_energy - self._last_bass_energy
        self._last_bass_energy = bass_energy
        self._centroid_proxy = self._treble_ratio_ema - self._bass_ratio_ema
        centroid_delta = self._centroid_proxy - self._last_centroid_proxy
        self._last_centroid_proxy = self._centroid_proxy

        variance_norm = self._variance_ema / max(self._energy_ema * self._energy_ema, 1e-6)
        spectral_shift = abs(self._bass_ratio_ema - self._bass_ratio_long) + abs(self._mid_ratio_ema - self._mid_ratio_long) + abs(
            self._treble_ratio_ema - self._treble_ratio_long
        )
        transient_spike = total_energy - rolling_energy
        self._beat_confidence = beat_confidence
        beat_conf = self._beat_confidence if self._beat_confidence > 0.0 else self._beat_ema

        scores = self._compute_phrase_scores(
            variance_norm,
            spectral_shift,
            transient_spike,
            bass_energy_delta,
            centroid_delta,
            beat_conf,
        )
        self._last_scores = scores

        if osc_beat:
            self._osc_beat_seen = True
            self._register_beat(scores)
        elif not self._osc_beat_seen and beat:
            self._register_beat(scores)

        candidate = self._select_candidate(scores)
        previous = self._current_state
        self._update_state(candidate, scores)
        if previous != self._current_state:
            return self._current_state
        return None

    def _compute_phrase_scores(
        self,
        variance_norm: float,
        spectral_shift: float,
        transient_spike: float,
        bass_energy_delta: float,
        centroid_delta: float,
        beat_conf: float,
    ) -> Dict[str, float]:
        if self._energy_ema <= self.silence_threshold:
            return {
                self.state_impact: 0.0,
                self.state_drop: 0.0,
                self.state_build: 0.0,
                self.state_groove: 0.0,
                self.state_breakdown: 0.0,
                self.state_switchup: 0.0,
                self.state_fill: 0.0,
            }

        energy_norm = clamp(
            (self._energy_ema - self.low_energy_threshold)
            / max(self.high_energy_threshold - self.low_energy_threshold, 1e-4),
            0.0,
            1.0,
        )
        transient_score = clamp(transient_spike / self.impact_energy_delta_threshold, 0.0, 1.0)
        beat_score = clamp((beat_conf - 0.65) / 0.35, 0.0, 1.0)
        pulse_score = clamp((self._pulse_ema - self.pulse_sparse_threshold) / (1.0 - self.pulse_sparse_threshold), 0.0, 1.0)

        drop_score = (
            clamp((beat_conf - 0.7) / 0.3, 0.0, 1.0) * 0.3
            + clamp(bass_energy_delta / self.drop_energy_delta_threshold, 0.0, 1.0) * 0.35
            + clamp(-centroid_delta / self.centroid_drop_threshold, 0.0, 1.0) * 0.2
            + pulse_score * 0.15
        )

        build_score = (
            clamp((self._movement_ema - self.build_slope_threshold) / (self.build_slope_threshold * 3.0), 0.0, 1.0) * 0.4
            + clamp((self._treble_ratio_ema - self.treble_ratio_high) / (1.0 - self.treble_ratio_high), 0.0, 1.0) * 0.2
            + pulse_score * 0.2
            + energy_norm * 0.2
        )

        ratio_stable = 1.0 - clamp(spectral_shift / self.bridge_shift_threshold, 0.0, 1.0)
        movement_flat = 1.0 - clamp(abs(self._movement_ema) / (self.build_slope_threshold * 4.0), 0.0, 1.0)
        variance_ok = 1.0 - clamp((variance_norm - self.variance_low_threshold) / self.variance_high_threshold, 0.0, 1.0)
        groove_score = beat_score * 0.4 + ratio_stable * 0.3 + movement_flat * 0.2 + variance_ok * 0.1

        bass_drop = clamp((self.bass_ratio_low - self._bass_ratio_ema) / self.bass_ratio_low, 0.0, 1.0)
        beat_lo = clamp((0.55 - beat_conf) / 0.55, 0.0, 1.0)
        treble_dom = clamp((self._treble_ratio_ema - self.treble_ratio_high) / (1.0 - self.treble_ratio_high), 0.0, 1.0)
        energy_low = clamp((self.low_energy_threshold - self._energy_ema) / self.low_energy_threshold, 0.0, 1.0)
        breakdown_score = bass_drop * 0.4 + beat_lo * 0.25 + treble_dom * 0.2 + energy_low * 0.15

        switchup_score = (
            clamp((spectral_shift - self.bridge_shift_threshold) / self.bridge_shift_threshold, 0.0, 1.0) * 0.6
            + clamp((variance_norm - self.variance_low_threshold) / self.variance_high_threshold, 0.0, 1.0) * 0.2
            + clamp(abs(self._movement_ema) / (self.build_slope_threshold * 4.0), 0.0, 1.0) * 0.2
        )

        max_other = max(drop_score, build_score, groove_score, breakdown_score, switchup_score)
        fill_score = clamp(1.0 - max_other, 0.0, 1.0)

        return {
            self.state_impact: transient_score,
            self.state_drop: drop_score,
            self.state_build: build_score,
            self.state_groove: groove_score,
            self.state_breakdown: breakdown_score,
            self.state_switchup: switchup_score,
            self.state_fill: fill_score,
        }

    def _select_candidate(self, scores: Dict[str, float]) -> str:
        if self._energy_ema <= self.silence_threshold:
            return self.state_silence

        best_state = self.state_fill
        best_score = 0.0
        for state in [
            self.state_drop,
            self.state_build,
            self.state_groove,
            self.state_breakdown,
            self.state_switchup,
        ]:
            score = float(scores.get(state, 0.0))
            if score > best_score:
                best_score = score
                best_state = state

        if best_score >= self.enter_threshold:
            if best_state == self.state_drop and self._drop_run_beats < self.drop_confirm_beats:
                return self._current_state
            if best_state == self.state_build and self._build_run_beats < self.build_confirm_beats:
                return self._current_state
            if best_state == self.state_switchup and self._switchup_run_beats < self.switchup_confirm_beats:
                return self._current_state
            return best_state

        if self._weak_score_beats >= self.fallback_weak_beats:
            return self.state_fill

        return self._current_state

    def _update_state(self, candidate: str, scores: Dict[str, float]) -> None:
        beats_in_phrase = self._beat_index - self._phrase_enter_beat
        if candidate == self.state_silence and self._current_state != self.state_silence:
            self._set_state(self.state_silence)
            return
        if self._current_state == self.state_silence and candidate != self.state_silence:
            self._set_state(candidate)
            return
        if self._current_state == self.state_impact:
            if candidate == self.state_silence:
                self._set_state(self.state_silence)
                return
            if float(scores.get(self.state_drop, 0.0)) >= self.drop_override_threshold:
                self._set_state(self.state_drop)
                return
            if beats_in_phrase >= self._min_beats_for(self.state_impact) and self._impact_return_state:
                self._set_state(self._impact_return_state)
            return

        if float(scores.get(self.state_impact, 0.0)) >= self.impact_trigger_threshold:
            self._impact_return_state = self._current_state
            self._set_state(self.state_impact)
            return

        min_beats = self._min_beats_for(self._current_state)
        if beats_in_phrase < min_beats and float(scores.get(self.state_drop, 0.0)) < self.drop_override_threshold:
            return

        if candidate == self._current_state:
            return

        if candidate == self.state_fill and self._weak_score_beats < self.fallback_weak_beats:
            return

        self._set_state(candidate)

    def _set_state(self, next_state: str) -> None:
        if next_state == self.state_impact and self._current_state != self.state_impact:
            self._impact_return_state = self._current_state
        self._current_state = next_state
        self._phrase_enter_beat = self._beat_index

    def _min_beats_for(self, state: str) -> int:
        if state == self.state_silence:
            return 0
        if state == self.state_impact:
            return 2
        if state == self.state_drop:
            return 4
        if state == self.state_build:
            return 8
        if state == self.state_groove:
            return 16
        if state == self.state_breakdown:
            return 8
        if state == self.state_switchup:
            return 8
        if state == self.state_fill:
            return 4
        return 4

    def _register_beat(self, scores: Dict[str, float]) -> None:
        self._beat_index += 1
        if float(scores.get(self.state_drop, 0.0)) >= self.enter_threshold:
            self._drop_run_beats += 1
        else:
            self._drop_run_beats = 0

        if float(scores.get(self.state_build, 0.0)) >= self.enter_threshold:
            self._build_run_beats += 1
        else:
            self._build_run_beats = 0

        if float(scores.get(self.state_switchup, 0.0)) >= self.enter_threshold:
            self._switchup_run_beats += 1
        else:
            self._switchup_run_beats = 0

        max_score = 0.0
        for state in [
            self.state_drop,
            self.state_build,
            self.state_groove,
            self.state_breakdown,
            self.state_switchup,
        ]:
            max_score = max(max_score, float(scores.get(state, 0.0)))
        if max_score < self.weak_score_threshold:
            self._weak_score_beats += 1
        else:
            self._weak_score_beats = 0
