# Light Controls

This document summarizes the controls exposed on the light-related scripts in this project. It focuses on exported inspector properties and runtime methods that directly affect light behavior.

## PartyLight (`PartyLight.gd`)
Scripted light type: `SpotLight3D`

Inspector (exported) controls:
- `sweep_speed` (float): Authoring-time sweep speed value (not currently used in the script logic).
- `min_energy` (float): Lower clamp for light intensity.
- `max_energy` (float): Upper clamp for light intensity.
- `light_groups` (Array[String]): Tagging/grouping metadata for the light.

Runtime controls:
- `set_z_sweep(value: float)`: Sweeps the light orientation along world Z.
  - `value` is clamped to `[-1, 1]`.
  - `1` points to world forward (-Z), `0` uses the authored rotation, `-1` points to world back (+Z).
- `set_light_energy(energy: float)`: Sets `light_energy`, clamped to `[min_energy, max_energy]`.

## RingRotator (`PartyLightRing.gd`)
Scripted rig type: `Node3D` used to rotate a ring of lights.

Inspector (exported) controls:
- `rotate_speed_radians` (float): Authoring-time rotation speed (not currently used in the script logic).

Runtime controls:
- `set_ring_rotation(angle_radians: float)`: Sets the ring rotation around its local Y axis.

## StrobeController (`Strobe.gd`)
Scripted controller type: `Node3D` that drives child `StrobeLight` nodes.

Inspector (exported) controls:
- `on_energy` (float): Energy level when the strobe is on.
- `off_energy` (float): Energy level when the strobe is off.

Runtime controls:
- `start_strobe(frequency_hz: float, duration_sec: float)`: Starts strobing at the given frequency for the given duration.
- `stop_strobe()`: Stops strobing and restores original light energy values.
- `pulse(peak_energy: float, duration_sec: float)`: One-shot pulse that ramps up to `peak_energy` then back down over `duration_sec`.

Notes:
- Requires `StrobeLight` children. If none are present, it warns and does nothing.
- `pulse` cancels any active strobe and restores all lights when complete.

## StrobeLight (`StrobeLight.gd`)
Scripted light type: `OmniLight3D`

Inspector (exported) controls:
- `light_groups` (Array[String]): Tagging/grouping metadata for the light.

Runtime controls:
- `set_strobe_energy(e: float)`: Immediately sets the light energy.
- `restore_energy()`: Restores the energy value that was set in the inspector at startup.

## LightController (`LightController.gd`)
This is the input/cue router for lighting, not a light itself. It exposes inputs and signals used to drive lights.

Inspector (exported) controls:
- `osc_path` (NodePath): Where to find an `OscClockReceiver` for external timing/cue input.
- `analyzer_path` (NodePath): Where to find a `SpectrumAudioAnalyzer` for audio-reactive cues.
- `phrase_detector_path` (NodePath): Where to find a `PhraseInspector` for phrase-based cues.

Signals emitted (inputs you can hook to drive lights):
- `osc_beat(beat_id: int)`
- `osc_bpm_changed(bpm: float)`
- `osc_confidence_changed(confidence: float)`
- `spectrum_cues(bass, mid, treble, beat, pulse, movement)`
- `standardized_cues(payload: Dictionary)`
