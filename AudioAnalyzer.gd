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

# Smoothing / sensitivity
@export var gain: float = 1.5
@export var smooth: float = 0.25
@export var noise_floor: float = 0.002

# Beat/pulse detection
@export var beat_flux_thresh: float = 0.010
@export var beat_refractory: float = 0.22
@export var pulse_flux_thresh: float = 0.016
@export var pulse_refractory: float = 0.08

# Movement (trend): positive = rising, negative = falling
@export var movement_smooth: float = 0.10

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

	var b: float = _band_energy(bass_lo, bass_hi) * gain
	var m: float = _band_energy(mid_lo, mid_hi) * gain
	var t: float = _band_energy(treble_lo, treble_hi) * gain

	# Noise floor clamp (THIS MUST BE HERE)
	b = 0.0 if b < noise_floor else b
	m = 0.0 if m < noise_floor else m
	t = 0.0 if t < noise_floor else t

	# Smooth bands
	_b_s = lerp(_b_s, b, smooth)
	_m_s = lerp(_m_s, m, smooth)
	_t_s = lerp(_t_s, t, smooth)

	# Flux detection (simple, robust)
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

	# Movement = trend of total energy
	var energy: float = _b_s + _m_s + _t_s
	var prev_energy: float = _energy_s
	_energy_s = lerp(_energy_s, energy, movement_smooth)
	var movement: float = _energy_s - prev_energy
	_movement_s = lerp(_movement_s, movement, 0.35)

	spectrum_cues.emit(_b_s, _m_s, _t_s, beat, pulse, _movement_s)

func _band_energy(lo_hz: float, hi_hz: float) -> float:
	# Godot returns Vector2 magnitudes; take length to get scalar energy
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
