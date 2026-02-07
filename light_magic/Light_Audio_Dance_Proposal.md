# Light + Audio Dance Proposal (Godot)

Goal: connect the audio service (OSC) to existing light controls to create a compelling, evolving display for dancing. This design uses clear mappings plus timed “scenes” that cycle for variety.

## 1) Wiring (Nodes + Signals)

Scene nodes (example):
- `AudioServiceOSC` (script: `light_magic/audio_service_osc.gd`)
- `LightController` (script: `light_magic/LightController.gd` or project `LightController.gd`)
- `PartyLight` nodes (spot lights)
- `PartyLightRing` node (ring rotator)
- `Strobe` node (strobe controller with `StrobeLight` children)

Connections:
- `AudioServiceOSC.endpoint_updated` -> `LightAudioDirector._on_audio_update` (new script that orchestrates cues)
- Optionally use `LightController.standardized_cues` if you already have it in-scene. The proposal below assumes direct use of `AudioServiceOSC` values for fine-grained access.

Recommended `AudioServiceOSC.endpoint_names` to subscribe:
- `/clock/beat`, `/clock/beat_id`, `/clock/bpm`, `/clock/conf`
- `/audio/bass`, `/audio/mid`, `/audio/treble`
- `/audio/total_energy`, `/audio/energy_delta`, `/audio/movement`
- `/audio/beat`, `/audio/pulse`
- `/audio/band_normalized_bass_1`, `/audio/band_normalized_mid_1`, `/audio/band_normalized_high_2`
- `/audio/band_presence_bass_1`, `/audio/band_presence_mid_1`, `/audio/band_presence_high_2`
- `/audio/beat_norm_band_win_30`, `/audio/beat_norm_band_win_60`

## 2) Core Mapping (Always On)

These mappings run in every scene to keep the show grounded in the music.

**PartyLight energy**
- `energy = clamp(min_energy + total_energy * 2.0, min_energy, max_energy)`
- Add a small “movement” shimmer: `energy += movement * 0.25`

**PartyLight sweep (Z)**
- `z_sweep = clamp((bass_ratio * 2.0) - 1.0, -1.0, 1.0)`
- If `band_presence_high_2 == 1`, add a quick jitter: `z_sweep += (randf() - 0.5) * 0.1`

**Ring rotation**
- `ring_rot = ring_rot + (bpm / 60.0) * 0.3 * delta`
- If `pulse` is true, add a brief acceleration: `ring_rot += 0.15`

**Strobe**
- On each `/audio/beat`, call `pulse(peak_energy = 2.0, duration_sec = 0.08)`
- If `energy_delta > 0.15`, call `pulse(peak_energy = 2.5, duration_sec = 0.05)`

## 3) Scene System (Variety + Evolution)

The display cycles scenes over time. Each scene reweights mappings or introduces distinct behavior. Scene changes are triggered on beat windows for musical alignment.

**Scene duration**
- Default: 32 beats (change on the next beat after 32 beats)
- If `clock/conf < 0.3`, extend to 48 beats to avoid jitter

**Scene selection**
- Use `/audio/beat_norm_band_win_30` as a driver. Example:
  - If winner is 0–2 (sub/bass), choose a bass-forward scene.
  - If winner is 3–6 (low-mid/mid), choose a mid-focused scene.
  - If winner is 7–10 (high/air), choose a treble sparkle scene.
- Rotate through a short queue to prevent repeats: keep last 2 scenes and avoid them if possible.

### Scene A: “Bass Gravity”
- Emphasis: kick + sub movement.
- PartyLight energy weight: `bass * 1.5`, `mid * 0.5`, `treble * 0.3`
- Z sweep: stronger: `z_sweep = clamp((bass * 2.5) - 1.2, -1, 1)`
- Ring rotation: slower, heavy feel: `ring_rot_speed = bpm * 0.15`
- Strobe: only on `audio/beat`, no extra pulses

### Scene B: “Mid Bloom”
- Emphasis: melodic body and vocals.
- PartyLight energy: `mid * 1.6`, `bass * 0.7`, `treble * 0.7`
- Z sweep: gentle sinusoidal sway: `z_sweep = sin(beat_id * 0.35)`
- Ring rotation: medium: `ring_rot_speed = bpm * 0.25`
- Strobe: pulse on `audio/pulse` (short and softer)

### Scene C: “Treble Spark”
- Emphasis: hats, shimmer, sparkle.
- PartyLight energy: `treble * 1.8`, `mid * 0.8`, `bass * 0.4`
- Z sweep: micro jitter on treble presence
- Ring rotation: faster: `ring_rot_speed = bpm * 0.4`
- Strobe: frequent light pings on `audio/pulse`

### Scene F: “Mix Madness”
- Emphasis: a hybrid of A/B/C where each color channel follows a different scene’s weighting.
- On enter, randomly assign scene weight profiles to color channels:
  - Example: `R = Scene A weights`, `G = Scene B weights`, `B = Scene C weights`
  - Shuffle this assignment every time the scene starts.
- PartyLight energy per color channel:
  - `R = (bass * A_r) + (mid * A_g) + (treble * A_b)` using Scene A multipliers
  - `G = (bass * B_r) + (mid * B_g) + (treble * B_b)` using Scene B multipliers
  - `B = (bass * C_r) + (mid * C_g) + (treble * C_b)` using Scene C multipliers
- Z sweep: use the dominant channel’s scene rule (the channel with highest output that frame).
- Ring rotation: medium-fast: `ring_rot_speed = bpm * 0.3`
- Strobe: pulse on `audio/beat`, plus occasional `audio/pulse` if treble presence is high.

### Scene D: “Energy Surge”
- Trigger when `total_energy > 1.2` and `movement > 0.2`
- PartyLight energy: `total_energy * 2.2`
- Z sweep: direct mapping to `energy_delta` for aggressive moves
- Ring rotation: burst: +0.5 each beat for 8 beats
- Strobe: start short strobe: `start_strobe(frequency_hz = bpm / 15.0, duration_sec = 2.0)`

### Scene E: “Breathing Space”
- Trigger when `total_energy < 0.6` for 8 beats
- PartyLight energy: lower clamp with slow pulse: `min_energy + 0.2 * sin(time * 0.5)`
- Z sweep: near 0 (authored rotation)
- Ring rotation: very slow: `bpm * 0.1`
- Strobe: off

## 4) Scene Transition Behavior

To avoid hard jumps, cross-fade between scene weights over 4 beats:
- Maintain a `scene_blend` value from 0.0 to 1.0
- `scene_blend += 1.0 / 4.0` per beat
- Apply `lerp(old_weights, new_weights, scene_blend)` to mapping weights

## 5) Minimal Implementation Sketch (New Script)

Create `LightAudioDirector.gd` (or similar) that:
- Caches references to all `PartyLight`, `PartyLightRing`, `Strobe`
- Subscribes to `AudioServiceOSC.endpoint_updated`
- Tracks beat count, current scene, and scene timer
- Applies the mappings in `_process(delta)` and in beat callbacks

## 6) Why This Feels Compelling

- The lights always respond to audio (energy, movement, beat)
- The scene system introduces “chapters” that feel deliberate
- Mapping emphasis shifts by band statistics, which matches the song’s character
- Transitions are beat-aligned and cross-faded, preventing harsh switches

---

If you want, I can implement the `LightAudioDirector.gd` and wire it into a scene next.
