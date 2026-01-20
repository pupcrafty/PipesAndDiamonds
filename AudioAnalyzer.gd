extends AudioStreamPlayer
class_name SpectrumAudioAnalyzer

signal spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float)

@export var mic_bus_name: String = "Mic"
@export var force_input_device: String = "Microphone (HyperX QuadCast)"

# Frequency bands (Hz)
@export var bass_lo: float = 40.0
@export var bass_hi: float = 160.0
@export var mid_lo: float = 160.0
@export var mid_hi: float = 1200.0
@export var treble_lo: float = 1200.0
@export var treble_hi: float = 8000.0

# Base gain + smoothing
@export var gain: float = 1.5
@export var smooth: float = 0.25

# --- NEW: Auto-normalization ---
@export var auto_normalize: bool = true
@export var loudness_smooth: float = 0.08          # lower = slower adaptation
@export var target_level: float = 0.08             # “typical” total energy after normalization
@export var min_norm: float = 0.25                 # don’t over-dampen loud parts too much
@export var max_norm: float = 8.0                  # don’t boost quiet parts infinitely
@export var silence_gate: float = 0.0006           # if raw energy below this, treat as silence (prevents insane boost)

# Noise floor (applied AFTER normalization)
@export var noise_floor: float = 0.002
@export var noise_floor_ratio_of_target: float = 0.04  # adaptive floor = target_level * ratio

# Beat/pulse detection
@export var beat_flux_thresh: float = 0.010
@export var beat_refractory: float = 0.22
@export var pulse_flux_thresh: float = 0.016
@export var pulse_refractory: float = 0.08

# Movement (trend): positive = rising, negative = falling
@export var movement_smooth: float = 0.10

# Debug
@export var debug_print: bool = false
@export var debug_print_every_sec: float = 0.25

var _spec: AudioEffectSpectrumAnalyzerInstance
var _beat_cd: float = 0.0
var _pulse_cd: float = 0.0

# Smoothed band energies
var _b_s: float = 0.0
var _m_s: float = 0.0
var _t_s: float = 0.0

# Previous values for “spectral flux”-ish detection
var _b_prev: float = 0.0
var _t_prev: float = 0.0

# Movement state
var _energy_s: float = 0.0
var _movement_s: float = 0.0

# Loudness normalization state (raw pre-gain energy EMA)
var _loudness_ema: float = 0.0

# Debug timer
var _dbg_t: float = 0.0


func _ready() -> void:
	if force_input_device != "":
		AudioServer.input_device = force_input_device

	if not playing:
		play()

	_spec = _find_spectrum_instance(mic_bus_name)
	if _spec == null:
		push_error("SpectrumAudioAnalyzer: No Spectrum Analyzer instance on bus '%s'" % mic_bus_name)
		set_process(false)
		return


func _process(delta: float) -> void:
	if _spec == null:
		return

	_beat_cd = maxf(_beat_cd - delta, 0.0)
	_pulse_cd = maxf(_pulse_cd - delta, 0.0)

	# --- 1) Read RAW energies (no gain, no normalization) ---
	var b_raw: float = _band_energy(bass_lo, bass_hi)
	var m_raw: float = _band_energy(mid_lo, mid_hi)
	var t_raw: float = _band_energy(treble_lo, treble_hi)
	var energy_raw: float = b_raw + m_raw + t_raw

	# --- 2) Update loudness EMA ---
	_loudness_ema = lerpf(_loudness_ema, energy_raw, loudness_smooth)

	# --- 3) Compute normalization multiplier (optional) ---
	var norm: float = 1.0
	if auto_normalize:
		# Gate: if basically silence, do not boost like crazy
		if _loudness_ema <= silence_gate:
			norm = 0.0
		else:
			norm = target_level / maxf(_loudness_ema, 0.000001)
			norm = clampf(norm, min_norm, max_norm)

	# --- 4) Apply gain + normalization ---
	var b: float = b_raw * gain * norm
	var m: float = m_raw * gain * norm
	var t: float = t_raw * gain * norm

	# --- 5) Noise floor clamp (after normalization) ---
	# Adaptive floor tied to target level keeps behavior consistent across loud/quiet sections.
	var adaptive_floor: float = maxf(noise_floor, target_level * noise_floor_ratio_of_target)
	if b < adaptive_floor: b = 0.0
	if m < adaptive_floor: m = 0.0
	if t < adaptive_floor: t = 0.0

	# --- 6) Smooth bands ---
	_b_s = lerpf(_b_s, b, smooth)
	_m_s = lerpf(_m_s, m, smooth)
	_t_s = lerpf(_t_s, t, smooth)

	# --- 7) Flux detection ---
	var bass_flux: float = maxf(_b_s - _b_prev, 0.0)
	var treble_flux: float = maxf(_t_s - _t_prev, 0.0)
	_b_prev = _b_s
	_t_prev = _t_s

	var beat := false
	if _beat_cd <= 0.0 and bass_flux >= beat_flux_thresh:
		beat = true
		_beat_cd = beat_refractory

	var pulse := false
	if _pulse_cd <= 0.0 and treble_flux >= pulse_flux_thresh:
		pulse = true
		_pulse_cd = pulse_refractory

	# --- 8) Movement = trend of total energy ---
	var energy: float = _b_s + _m_s + _t_s
	var prev_energy: float = _energy_s
	_energy_s = lerpf(_energy_s, energy, movement_smooth)
	var movement: float = _energy_s - prev_energy
	_movement_s = lerpf(_movement_s, movement, 0.35)

	# --- 9) Debug output ---
	if debug_print:
		_dbg_t += delta
		if _dbg_t >= debug_print_every_sec:
			_dbg_t = 0.0
			print(
				"raw=", snappedf(energy_raw, 0.000001),
				" ema=", snappedf(_loudness_ema, 0.000001),
				" norm=", snappedf(norm, 0.001),
				" b=", snappedf(_b_s, 0.0001),
				" bf=", snappedf(bass_flux, 0.0001),
				" beat=", beat,
				" tf=", snappedf(treble_flux, 0.0001),
				" pulse=", pulse
			)

	spectrum_cues.emit(_b_s, _m_s, _t_s, beat, pulse, _movement_s)


func _band_energy(lo_hz: float, hi_hz: float) -> float:
	var v: Vector2 = _spec.get_magnitude_for_frequency_range(lo_hz, hi_hz)
	return v.length()


func _find_spectrum_instance(bus_name: String) -> AudioEffectSpectrumAnalyzerInstance:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return null
	for i: int in range(AudioServer.get_bus_effect_count(bus)):
		var fx: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectSpectrumAnalyzer:
			var inst := AudioServer.get_bus_effect_instance(bus, i)
			return inst as AudioEffectSpectrumAnalyzerInstance
	return null
