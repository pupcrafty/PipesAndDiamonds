extends Node
class_name PhraseInspector

signal phrase_changed(phrase: String)

const STATE_SILENCE := "SILENCE / VOID"
const STATE_BUILD := "BUILD"
const STATE_FILL := "FILL"
const STATE_IMPACT := "IMPACT / HIT"
const STATE_DROP := "DROP"
const STATE_GROOVE := "GROOVE"
const STATE_BREAKDOWN := "BREAKDOWN"
const STATE_SWITCHUP := "SWITCHUP / GENRE FLIP"

@export var light_controller_path: NodePath

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
@export var centroid_drop_threshold: float = 0.035

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

@export var enter_threshold: float = 0.55
@export var weak_score_threshold: float = 0.35
@export var drop_override_threshold: float = 0.9
@export var impact_trigger_threshold: float = 0.7
@export var fallback_weak_beats: int = 3
@export var drop_confirm_beats: int = 4
@export var build_confirm_beats: int = 4
@export var switchup_confirm_beats: int = 8

var _light_controller: LightController
var _current_state: String = STATE_SILENCE
var _beat_index: int = 0
var _phrase_enter_beat: int = 0
var _impact_return_state: String = ""
var _bpm: float = 120.0
var _beat_confidence: float = 0.0
var _osc_beat_seen: bool = false
var _drop_run_beats: int = 0
var _build_run_beats: int = 0
var _switchup_run_beats: int = 0
var _weak_score_beats: int = 0
var _last_scores: Dictionary = {}

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

var _last_bass_energy: float = 0.0
var _centroid_proxy: float = 0.0
var _last_centroid_proxy: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_light_controller = _get_light_controller()
	if _light_controller != null:
		_light_controller.standardized_cues.connect(_on_standardized_cues)
		_light_controller.osc_bpm_changed.connect(_on_osc_bpm_changed)
		_light_controller.osc_confidence_changed.connect(_on_osc_confidence_changed)
		_light_controller.osc_beat.connect(_on_osc_beat)
	else:
		push_warning("PhraseInspector: LightController not found.")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_standardized_cues(payload: Dictionary) -> void:
	if not payload.has("total_energy"):
		return

	var total_energy: float = payload["total_energy"]
	var movement: float = payload.get("movement", 0.0)
	var variance: float = payload.get("energy_variance", 0.0)
	var beat: bool = payload.get("beat", false)
	var pulse: bool = payload.get("pulse", false)
	var bass_ratio: float = payload.get("bass_ratio", 0.0)
	var mid_ratio: float = payload.get("mid_ratio", 0.0)
	var treble_ratio: float = payload.get("treble_ratio", 0.0)
	var rolling_energy := _energy_ema
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

	var bass_energy := total_energy * bass_ratio
	var bass_energy_delta := bass_energy - _last_bass_energy
	_last_bass_energy = bass_energy
	_centroid_proxy = _treble_ratio_ema - _bass_ratio_ema
	var centroid_delta := _centroid_proxy - _last_centroid_proxy
	_last_centroid_proxy = _centroid_proxy

	var variance_norm := _variance_ema / maxf(_energy_ema * _energy_ema, 0.000001)
	var spectral_shift := (
		abs(_bass_ratio_ema - _bass_ratio_long)
		+ abs(_mid_ratio_ema - _mid_ratio_long)
		+ abs(_treble_ratio_ema - _treble_ratio_long)
	)
	var transient_spike := total_energy - rolling_energy
	var beat_conf := _beat_confidence if _beat_confidence > 0.0 else _beat_ema

	var scores := _compute_phrase_scores(
		variance_norm,
		spectral_shift,
		transient_spike,
		bass_energy_delta,
		centroid_delta,
		beat_conf
	)
	_last_scores = scores
	if not _osc_beat_seen and beat:
		_register_beat(scores)

	var candidate := _select_candidate(scores)
	_update_state(candidate, scores)


func _compute_phrase_scores(
	variance_norm: float,
	spectral_shift: float,
	transient_spike: float,
	bass_energy_delta: float,
	centroid_delta: float,
	beat_conf: float
) -> Dictionary:
	if _energy_ema <= silence_threshold:
		return {
			STATE_IMPACT: 0.0,
			STATE_DROP: 0.0,
			STATE_BUILD: 0.0,
			STATE_GROOVE: 0.0,
			STATE_BREAKDOWN: 0.0,
			STATE_SWITCHUP: 0.0,
			STATE_FILL: 0.0
		}

	var energy_norm := clampf(
		(_energy_ema - low_energy_threshold) / maxf(high_energy_threshold - low_energy_threshold, 0.0001),
		0.0,
		1.0
	)
	var transient_score := clampf(transient_spike / impact_energy_delta_threshold, 0.0, 1.0)
	var beat_score := clampf((beat_conf - 0.65) / 0.35, 0.0, 1.0)
	var pulse_score := clampf((_pulse_ema - pulse_sparse_threshold) / (1.0 - pulse_sparse_threshold), 0.0, 1.0)

	var drop_score := (
		clampf((beat_conf - 0.7) / 0.3, 0.0, 1.0) * 0.3
		+ clampf(bass_energy_delta / drop_energy_delta_threshold, 0.0, 1.0) * 0.35
		+ clampf(-centroid_delta / centroid_drop_threshold, 0.0, 1.0) * 0.2
		+ pulse_score * 0.15
	)

	var build_score := (
		clampf((_movement_ema - build_slope_threshold) / (build_slope_threshold * 3.0), 0.0, 1.0) * 0.4
		+ clampf((_treble_ratio_ema - treble_ratio_high) / (1.0 - treble_ratio_high), 0.0, 1.0) * 0.2
		+ pulse_score * 0.2
		+ energy_norm * 0.2
	)

	var ratio_stable := 1.0 - clampf(spectral_shift / bridge_shift_threshold, 0.0, 1.0)
	var movement_flat := 1.0 - clampf(abs(_movement_ema) / (build_slope_threshold * 4.0), 0.0, 1.0)
	var variance_ok := 1.0 - clampf((variance_norm - variance_low_threshold) / variance_high_threshold, 0.0, 1.0)
	var groove_score := (
		beat_score * 0.4
		+ ratio_stable * 0.3
		+ movement_flat * 0.2
		+ variance_ok * 0.1
	)

	var bass_drop := clampf((bass_ratio_low - _bass_ratio_ema) / bass_ratio_low, 0.0, 1.0)
	var beat_lo := clampf((0.55 - beat_conf) / 0.55, 0.0, 1.0)
	var treble_dom := clampf((_treble_ratio_ema - treble_ratio_high) / (1.0 - treble_ratio_high), 0.0, 1.0)
	var energy_low := clampf((low_energy_threshold - _energy_ema) / low_energy_threshold, 0.0, 1.0)
	var breakdown_score := (
		bass_drop * 0.4
		+ beat_lo * 0.25
		+ treble_dom * 0.2
		+ energy_low * 0.15
	)

	var switchup_score := (
		clampf((spectral_shift - bridge_shift_threshold) / bridge_shift_threshold, 0.0, 1.0) * 0.6
		+ clampf((variance_norm - variance_low_threshold) / variance_high_threshold, 0.0, 1.0) * 0.2
		+ clampf(abs(_movement_ema) / (build_slope_threshold * 4.0), 0.0, 1.0) * 0.2
	)

	var max_other := maxf(drop_score, maxf(build_score, maxf(groove_score, maxf(breakdown_score, switchup_score))))
	var fill_score := clampf(1.0 - max_other, 0.0, 1.0)

	return {
		STATE_IMPACT: transient_score,
		STATE_DROP: drop_score,
		STATE_BUILD: build_score,
		STATE_GROOVE: groove_score,
		STATE_BREAKDOWN: breakdown_score,
		STATE_SWITCHUP: switchup_score,
		STATE_FILL: fill_score
	}


func _select_candidate(scores: Dictionary) -> String:
	if _energy_ema <= silence_threshold:
		return STATE_SILENCE

	var best_state := STATE_FILL
	var best_score := 0.0
	for state in [STATE_DROP, STATE_BUILD, STATE_GROOVE, STATE_BREAKDOWN, STATE_SWITCHUP]:
		var score := float(scores.get(state, 0.0))
		if score > best_score:
			best_score = score
			best_state = state

	if best_score >= enter_threshold:
		if best_state == STATE_DROP and _drop_run_beats < drop_confirm_beats:
			return _current_state
		if best_state == STATE_BUILD and _build_run_beats < build_confirm_beats:
			return _current_state
		if best_state == STATE_SWITCHUP and _switchup_run_beats < switchup_confirm_beats:
			return _current_state
		return best_state

	if _weak_score_beats >= fallback_weak_beats:
		return STATE_FILL

	return _current_state


func _update_state(candidate: String, scores: Dictionary) -> void:
	var beats_in_phrase := _beat_index - _phrase_enter_beat
	if candidate == STATE_SILENCE and _current_state != STATE_SILENCE:
		_set_state(STATE_SILENCE)
		return
	if _current_state == STATE_SILENCE and candidate != STATE_SILENCE:
		_set_state(candidate)
		return
	if _current_state == STATE_IMPACT:
		if candidate == STATE_SILENCE:
			_set_state(STATE_SILENCE)
			return
		if float(scores.get(STATE_DROP, 0.0)) >= drop_override_threshold:
			_set_state(STATE_DROP)
			return
		if beats_in_phrase >= _min_beats_for(STATE_IMPACT) and _impact_return_state != "":
			_set_state(_impact_return_state)
		return

	if float(scores.get(STATE_IMPACT, 0.0)) >= impact_trigger_threshold:
		_impact_return_state = _current_state
		_set_state(STATE_IMPACT)
		return

	var min_beats := _min_beats_for(_current_state)
	if beats_in_phrase < min_beats and float(scores.get(STATE_DROP, 0.0)) < drop_override_threshold:
		return

	if candidate == _current_state:
		return

	if candidate == STATE_FILL and _weak_score_beats < fallback_weak_beats:
		return

	_set_state(candidate)


func _set_state(next_state: String) -> void:
	if next_state == STATE_IMPACT and _current_state != STATE_IMPACT:
		_impact_return_state = _current_state
	_current_state = next_state
	_phrase_enter_beat = _beat_index
	phrase_changed.emit(_current_state)


func _min_beats_for(state: String) -> int:
	match state:
		STATE_SILENCE:
			return 0
		STATE_IMPACT:
			return 2
		STATE_DROP:
			return 4
		STATE_BUILD:
			return 8
		STATE_GROOVE:
			return 16
		STATE_BREAKDOWN:
			return 8
		STATE_SWITCHUP:
			return 8
		STATE_FILL:
			return 4
		_:
			return 4


func _register_beat(scores: Dictionary) -> void:
	_beat_index += 1
	if float(scores.get(STATE_DROP, 0.0)) >= enter_threshold:
		_drop_run_beats += 1
	else:
		_drop_run_beats = 0

	if float(scores.get(STATE_BUILD, 0.0)) >= enter_threshold:
		_build_run_beats += 1
	else:
		_build_run_beats = 0

	if float(scores.get(STATE_SWITCHUP, 0.0)) >= enter_threshold:
		_switchup_run_beats += 1
	else:
		_switchup_run_beats = 0

	var max_score := 0.0
	for state in [STATE_DROP, STATE_BUILD, STATE_GROOVE, STATE_BREAKDOWN, STATE_SWITCHUP]:
		max_score = maxf(max_score, float(scores.get(state, 0.0)))
	if max_score < weak_score_threshold:
		_weak_score_beats += 1
	else:
		_weak_score_beats = 0


func _on_osc_beat(_beat_id: int) -> void:
	_osc_beat_seen = true
	_register_beat(_last_scores)


func _on_osc_bpm_changed(bpm: float) -> void:
	_bpm = bpm


func _on_osc_confidence_changed(confidence: float) -> void:
	_beat_confidence = confidence


func _get_light_controller() -> LightController:
	if light_controller_path != NodePath(""):
		return get_node_or_null(light_controller_path) as LightController
	var nodes: Array[Node] = get_tree().get_root().find_children("", "LightController", true, false)
	return nodes[0] as LightController if not nodes.is_empty() else null
