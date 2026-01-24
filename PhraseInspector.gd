extends Node
class_name PhraseInspector

signal phrase_changed(phrase: String)

const STATE_SILENCE := "SILENCE / VOID"
const STATE_INTRO := "INTRO"
const STATE_BUILD := "BUILD"
const STATE_RISER := "RISER / LIFT"
const STATE_FILL := "FILL"
const STATE_IMPACT := "IMPACT / HIT"
const STATE_DROP := "DROP"
const STATE_PEAK := "PEAK / CHORUS"
const STATE_GROOVE := "GROOVE"
const STATE_HALFTIME := "HALFTIME"
const STATE_BREAKDOWN := "BREAKDOWN"
const STATE_BRIDGE := "BRIDGE / VARIATION"
const STATE_SWITCHUP := "SWITCHUP / GENRE FLIP"
const STATE_OUTRO := "OUTRO"

@export var light_controller_path: NodePath

@export var transition_confirm_time: float = 0.6
@export var micro_confirm_time: float = 0.12

@export var energy_smooth: float = 0.12
@export var trend_smooth: float = 0.18
@export var beat_smooth: float = 0.2
@export var ratio_long_smooth: float = 0.02

@export var silence_threshold: float = 0.01
@export var low_energy_threshold: float = 0.04
@export var high_energy_threshold: float = 0.14

@export var build_slope_threshold: float = 0.002
@export var outro_slope_threshold: float = -0.002

@export var impact_energy_delta_threshold: float = 0.04
@export var drop_energy_delta_threshold: float = 0.02

@export var beat_stable_threshold: float = 0.6
@export var beat_unstable_threshold: float = 0.25
@export var pulse_dense_threshold: float = 0.55
@export var pulse_sparse_threshold: float = 0.2

@export var bass_ratio_high: float = 0.45
@export var bass_ratio_low: float = 0.2
@export var treble_ratio_high: float = 0.45
@export var mid_ratio_focus: float = 0.45

@export var variance_high_threshold: float = 0.35
@export var variance_low_threshold: float = 0.12
@export var bridge_shift_threshold: float = 0.22

var _light_controller: LightController
var _current_state: String = STATE_SILENCE
var _candidate_state: String = ""
var _candidate_duration: float = 0.0
var _last_update_ms: int = 0

var _energy_ema: float = 0.0
var _movement_ema: float = 0.0
var _variance_ema: float = 0.0
var _beat_ema: float = 0.0
var _pulse_ema: float = 0.0

var _bass_ratio_ema: float = 0.0
var _mid_ratio_ema: float = 0.0
var _treble_ratio_ema: float = 0.0

var _bass_ratio_long: float = 0.0
var _mid_ratio_long: float = 0.0
var _treble_ratio_long: float = 0.0

var _last_energy: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_light_controller = _get_light_controller()
	if _light_controller != null:
		_light_controller.standardized_cues.connect(_on_standardized_cues)
	else:
		push_warning("PhraseInspector: LightController not found.")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_standardized_cues(payload: Dictionary) -> void:
	if not payload.has("total_energy"):
		return

	var now_ms := Time.get_ticks_msec()
	var dt := 0.0
	if _last_update_ms > 0:
		dt = float(now_ms - _last_update_ms) / 1000.0
	_last_update_ms = now_ms

	var total_energy: float = payload["total_energy"]
	var movement: float = payload.get("movement", 0.0)
	var variance: float = payload.get("energy_variance", 0.0)
	var beat: bool = payload.get("beat", false)
	var pulse: bool = payload.get("pulse", false)
	var bass_ratio: float = payload.get("bass_ratio", 0.0)
	var mid_ratio: float = payload.get("mid_ratio", 0.0)
	var treble_ratio: float = payload.get("treble_ratio", 0.0)
	var energy_delta: float = payload.get("energy_delta", total_energy - _last_energy)
	_last_energy = total_energy

	_energy_ema = lerpf(_energy_ema, total_energy, energy_smooth)
	_movement_ema = lerpf(_movement_ema, movement, trend_smooth)
	_variance_ema = lerpf(_variance_ema, variance, trend_smooth)
	_beat_ema = lerpf(_beat_ema, beat ? 1.0 : 0.0, beat_smooth)
	_pulse_ema = lerpf(_pulse_ema, pulse ? 1.0 : 0.0, beat_smooth)

	_bass_ratio_ema = lerpf(_bass_ratio_ema, bass_ratio, energy_smooth)
	_mid_ratio_ema = lerpf(_mid_ratio_ema, mid_ratio, energy_smooth)
	_treble_ratio_ema = lerpf(_treble_ratio_ema, treble_ratio, energy_smooth)

	_bass_ratio_long = lerpf(_bass_ratio_long, bass_ratio, ratio_long_smooth)
	_mid_ratio_long = lerpf(_mid_ratio_long, mid_ratio, ratio_long_smooth)
	_treble_ratio_long = lerpf(_treble_ratio_long, treble_ratio, ratio_long_smooth)

	var variance_norm := _variance_ema / maxf(_energy_ema * _energy_ema, 0.000001)
	var spectral_shift := (
		abs(_bass_ratio_ema - _bass_ratio_long)
		+ abs(_mid_ratio_ema - _mid_ratio_long)
		+ abs(_treble_ratio_ema - _treble_ratio_long)
	)

	var candidate := _classify_state(variance_norm, energy_delta, spectral_shift)
	_update_state(candidate, dt)


func _classify_state(variance_norm: float, energy_delta: float, spectral_shift: float) -> String:
	if _energy_ema <= silence_threshold:
		return STATE_SILENCE

	var beat_stable := _beat_ema >= beat_stable_threshold
	var beat_unstable := _beat_ema <= beat_unstable_threshold
	var pulse_dense := _pulse_ema >= pulse_dense_threshold
	var pulse_sparse := _pulse_ema <= pulse_sparse_threshold
	var variance_high := variance_norm >= variance_high_threshold
	var variance_low := variance_norm <= variance_low_threshold

	if energy_delta >= impact_energy_delta_threshold and _energy_ema >= low_energy_threshold:
		return STATE_IMPACT

	if pulse_dense and _treble_ratio_ema >= treble_ratio_high and variance_high:
		return STATE_FILL

	if _current_state in [STATE_BUILD, STATE_RISER, STATE_BREAKDOWN, STATE_INTRO] \
			and _bass_ratio_ema >= bass_ratio_high \
			and energy_delta >= drop_energy_delta_threshold:
		return STATE_DROP

	if beat_stable and _treble_ratio_ema >= treble_ratio_high and variance_high \
			and _movement_ema >= build_slope_threshold:
		return STATE_RISER

	if beat_stable and _movement_ema >= build_slope_threshold and _energy_ema >= low_energy_threshold:
		return STATE_BUILD

	if beat_stable and _energy_ema >= high_energy_threshold and variance_low:
		return STATE_PEAK

	if beat_stable and _energy_ema >= low_energy_threshold and variance_low:
		return STATE_GROOVE

	if beat_stable and _bass_ratio_ema >= bass_ratio_high and pulse_sparse:
		return STATE_HALFTIME

	if _energy_ema <= low_energy_threshold and _mid_ratio_ema >= mid_ratio_focus:
		return STATE_BREAKDOWN

	if beat_stable and spectral_shift >= bridge_shift_threshold and abs(_movement_ema) < build_slope_threshold:
		return STATE_BRIDGE

	if beat_unstable and variance_high:
		return STATE_SWITCHUP

	if _current_state in [STATE_GROOVE, STATE_PEAK] \
			and _movement_ema <= outro_slope_threshold \
			and _energy_ema < high_energy_threshold:
		return STATE_OUTRO

	return STATE_INTRO


func _update_state(candidate: String, dt: float) -> void:
	if candidate == _current_state:
		_candidate_state = ""
		_candidate_duration = 0.0
		return

	if candidate != _candidate_state:
		_candidate_state = candidate
		_candidate_duration = 0.0
	else:
		_candidate_duration += dt
		var required := transition_confirm_time
		if candidate in [STATE_FILL, STATE_IMPACT, STATE_SWITCHUP]:
			required = micro_confirm_time
		if _candidate_duration >= required:
			_set_state(candidate)


func _set_state(next_state: String) -> void:
	_current_state = next_state
	_candidate_state = ""
	_candidate_duration = 0.0
	phrase_changed.emit(_current_state)


func _get_light_controller() -> LightController:
	if light_controller_path != NodePath(""):
		return get_node_or_null(light_controller_path) as LightController
	var nodes: Array[Node] = get_tree().get_root().find_children("", "LightController", true, false)
	return nodes[0] as LightController if not nodes.is_empty() else null
