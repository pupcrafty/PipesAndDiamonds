extends Node
class_name LightController

# ============================================================
# Light Controller (Audio -> Lights)
# ============================================================

const GROUP_MODE_ALL: String = "all"
const GROUP_MODE_ALTERNATE: String = "alternate"
const GROUP_MODE_RANDOM: String = "random"

const PRESET_BASS: String = "bass"
const PRESET_TREBLE: String = "treble"
const PRESET_MOVEMENT: String = "movement"

@export var light_root_path: NodePath = NodePath(".")
@export var strobe_path: NodePath = NodePath("Strobe")

@export var enabled: bool = true
@export var debug_print: bool = false
@export var debug_print_every_sec: float = 0.2

@export var group_mode: String = GROUP_MODE_ALL
@export var group_overrides: Dictionary = {} # { "NodeNameOrPath": ["GroupA", "GroupB"] }
@export var group_sub_cue_presets: Dictionary = {} # { "GroupA": "bass" | "treble" | "movement" }

@export var osc_confidence_threshold: float = 0.7

# Normalize tiny analyzer values
@export var bass_normalize: float = 12.0
@export var mid_normalize: float = 10.0
@export var treble_normalize: float = 10.0

# Mapping + pulses
@export var bass_to_peak_scale: float = 40.0
@export var pulse_peak_min: float = 6.0
@export var pulse_peak_max: float = 20.0
@export var pulse_duration_sec: float = 0.20
@export var pulse_cooldown_sec: float = 0.10

# Intensity smoothing + ranges
@export var intensity_attack: float = 6.0
@export var intensity_release: float = 2.0
@export var default_min_energy: float = 0.0
@export var default_max_energy: float = 6.0
@export var beat_hit_boost: float = 0.25

# Movement + sparkle
@export var treble_sparkle_gain: float = 0.6
@export var movement_gain: float = 2.0
@export var ring_speed_scale: float = 4.0


class FrameCue:
	var bass: float = 0.0
	var mid: float = 0.0
	var treble: float = 0.0
	var beat: bool = false
	var pulse: bool = false
	var movement: float = 0.0
	var bpm: float = 0.0
	var has_bpm: bool = false


class LightEntry:
	var node: Node
	var groups: Array[String] = []
	var current_intensity: float = 0.0
	var min_energy: float = 0.0
	var max_energy: float = 0.0
	var has_set_energy: bool = false
	var has_light_energy: bool = false


class RotatorEntry:
	var node: Node
	var groups: Array[String] = []
	var current_speed: float = 0.0
	var has_speed_property: bool = false
	var has_set_speed: bool = false
	var speed_property: String = ""


var _strobe: StrobeController
var _analyzer: SpectrumAudioAnalyzer
var _osc: OscClockReceiver

var _pulse_cd: float = 0.0
var _debug_t: float = 0.0

var _last_cue: FrameCue = FrameCue.new()
var _has_cue: bool = false

var _osc_confidence: float = 0.0
var _osc_beat_pending: bool = false
var _osc_bpm: float = 0.0
var _osc_has_bpm: bool = false

var _lights: Array[LightEntry] = []
var _rotators: Array[RotatorEntry] = []
var _group_names: Array[String] = []
var _alternate_index: int = 0
var _last_hit_group: String = ""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ============================================================
# Ready / Discovery
# ============================================================

func _ready() -> void:
	_rng.randomize()
	_strobe = get_node_or_null(strobe_path) as StrobeController
	_analyzer = _find_analyzer()
	_osc = _find_osc()

	if _analyzer != null:
		_analyzer.spectrum_cues.connect(_on_spectrum_cues)
	else:
		push_warning("LightController: SpectrumAudioAnalyzer not found. No audio cues.")

	if _osc != null:
		_osc.beat.connect(_on_osc_beat)
		_osc.bpm_changed.connect(_on_osc_bpm)
		_osc.confidence_changed.connect(_on_osc_confidence)

	_discover_lights()

	print(
		"LightController ready. analyzer=",
		_analyzer != null,
		" osc=",
		_osc != null,
		" strobe=",
		_strobe != null,
		" lights=",
		_lights.size(),
		" rotators=",
		_rotators.size(),
		" groups=",
		_group_names
	)

	if _strobe == null:
		push_warning("LightController: StrobeController not found at strobe_path = " + str(strobe_path))


# ============================================================
# Public API
# ============================================================

func set_group_mode(mode: String) -> void:
	group_mode = mode.to_lower()


func set_enabled(is_enabled: bool) -> void:
	enabled = is_enabled


func trigger_test_pulse() -> void:
	var peak: float = lerpf(pulse_peak_min, pulse_peak_max, 0.7)
	_fire_strobe("ALL", peak, pulse_duration_sec)


func register_light(node: Node, groups: Array[String]) -> void:
	if node == null:
		return
	_add_light_node(node, groups)
	_refresh_group_names()


# ============================================================
# Signals / Input Handling
# ============================================================

func _on_spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float) -> void:
	_last_cue.bass = bass
	_last_cue.mid = mid
	_last_cue.treble = treble
	_last_cue.movement = movement
	_last_cue.beat = beat or _osc_beat_pending
	_last_cue.pulse = pulse
	_last_cue.bpm = _osc_bpm
	_last_cue.has_bpm = _osc_has_bpm
	_osc_beat_pending = false
	_has_cue = true

	if (_last_cue.beat or _last_cue.pulse) and _pulse_cd <= 0.0:
		var strength: float = clampf(_last_cue.bass * bass_to_peak_scale, 0.0, 1.0)
		var peak: float = lerpf(pulse_peak_min, pulse_peak_max, strength)
		var hit_group: String = _select_hit_group()
		_fire_strobe(hit_group, peak, pulse_duration_sec)
		_pulse_cd = pulse_cooldown_sec


func _on_osc_beat(_beat_id: int) -> void:
	if _osc_confidence >= osc_confidence_threshold:
		_osc_beat_pending = true


func _on_osc_bpm(bpm: float) -> void:
	_osc_bpm = bpm
	_osc_has_bpm = true


func _on_osc_confidence(confidence: float) -> void:
	_osc_confidence = confidence


# ============================================================
# Frame Update
# ============================================================

func _process(delta: float) -> void:
	if _pulse_cd > 0.0:
		_pulse_cd = maxf(0.0, _pulse_cd - delta)

	if not enabled or not _has_cue:
		return

	_apply_lights(delta)
	_apply_rotators(delta)

	if debug_print:
		_debug_t += delta
		if _debug_t >= debug_print_every_sec:
			_debug_t = 0.0
			print(
				"cue b=",
				snappedf(_last_cue.bass, 0.0001),
				" m=",
				snappedf(_last_cue.mid, 0.0001),
				" t=",
				snappedf(_last_cue.treble, 0.0001),
				" beat=",
				_last_cue.beat,
				" pulse=",
				_last_cue.pulse,
				" move=",
				snappedf(_last_cue.movement, 0.0001),
				" group=",
				_last_hit_group
			)


# ============================================================
# Light + Rotator Application
# ============================================================

func _apply_lights(delta: float) -> void:
	var bass_n: float = clampf(_last_cue.bass * bass_normalize, 0.0, 1.0)
	var mid_n: float = clampf(_last_cue.mid * mid_normalize, 0.0, 1.0)
	var treble_n: float = clampf(_last_cue.treble * treble_normalize, 0.0, 1.0)
	var movement_n: float = clampf(_last_cue.movement * movement_gain, -1.0, 1.0)

	for entry: LightEntry in _lights:
		var hit_group: String = _get_entry_hit_group(entry.groups)
		var is_hit_group: bool = _is_hit_group(entry.groups, hit_group)
		var target_intensity: float = _compute_intensity(bass_n, mid_n, treble_n, movement_n, hit_group, is_hit_group)

		var rate: float = intensity_attack if target_intensity > entry.current_intensity else intensity_release
		entry.current_intensity = move_toward(entry.current_intensity, target_intensity, rate * delta)

		var energy: float = lerpf(entry.min_energy, entry.max_energy, entry.current_intensity)
		if entry.has_set_energy:
			entry.node.call("set_light_energy", energy)
		elif entry.has_light_energy:
			entry.node.set("light_energy", energy)


func _apply_rotators(delta: float) -> void:
	var treble_n: float = clampf(_last_cue.treble * treble_normalize, 0.0, 1.0)
	var movement_n: float = clampf(_last_cue.movement * movement_gain, -1.0, 1.0)

	for entry: RotatorEntry in _rotators:
		var hit_group: String = _get_entry_hit_group(entry.groups)
		var is_hit_group: bool = _is_hit_group(entry.groups, hit_group)

		var weights: Vector3 = _preset_weights(hit_group)
		var target_speed: float = (movement_n * weights.z + treble_n * weights.y * treble_sparkle_gain) * ring_speed_scale
		if is_hit_group and (_last_cue.beat or _last_cue.pulse):
			target_speed *= 1.2

		var rate: float = intensity_attack if absf(target_speed) > absf(entry.current_speed) else intensity_release
		entry.current_speed = move_toward(entry.current_speed, target_speed, rate * delta)

		if entry.has_set_speed:
			entry.node.call("set_ring_speed", entry.current_speed)
		elif entry.has_speed_property and entry.speed_property != "":
			entry.node.set(entry.speed_property, entry.current_speed)


# ============================================================
# Computation Helpers
# ============================================================

func _compute_intensity(bass_n: float, mid_n: float, treble_n: float, movement_n: float, group_name: String, is_hit_group: bool) -> float:
	var weights: Vector3 = _preset_weights(group_name)
	var bass_term: float = bass_n * weights.x
	var mid_term: float = mid_n * 0.8
	var treble_term: float = treble_n * weights.y * (1.0 + treble_sparkle_gain)
	var move_term: float = movement_n * weights.z

	var combined: float = (bass_term + mid_term + treble_term) / 3.0
	combined += move_term * 0.25
	if is_hit_group and (_last_cue.beat or _last_cue.pulse):
		combined += beat_hit_boost
	return clampf(combined, 0.0, 1.0)


func _preset_weights(group_name: String) -> Vector3:
	var preset: String = _get_group_preset(group_name)
	match preset:
		PRESET_BASS:
			return Vector3(1.4, 0.8, 0.9)
		PRESET_TREBLE:
			return Vector3(0.8, 1.4, 0.9)
		PRESET_MOVEMENT:
			return Vector3(0.9, 0.8, 1.4)
		_:
			return Vector3(1.0, 1.0, 1.0)


func _get_group_preset(group_name: String) -> String:
	if group_sub_cue_presets.has(group_name):
		return str(group_sub_cue_presets[group_name]).to_lower()

	if _group_names.is_empty():
		return PRESET_BASS
	var idx: int = _group_names.find(group_name)
	if idx < 0:
		idx = 0
	match idx % 3:
		0:
			return PRESET_BASS
		1:
			return PRESET_TREBLE
		_:
			return PRESET_MOVEMENT


func _get_entry_hit_group(groups: Array[String]) -> String:
	if group_mode == GROUP_MODE_ALL:
		_last_hit_group = "ALL"
		return "ALL"

	if groups.is_empty():
		return "ALL"

	if _last_hit_group == "":
		_last_hit_group = groups[0]
	return _last_hit_group


func _is_hit_group(groups: Array[String], hit_group: String) -> bool:
	if group_mode == GROUP_MODE_ALL:
		return true
	if hit_group == "ALL":
		return true
	return groups.has(hit_group)


func _select_hit_group() -> String:
	if group_mode == GROUP_MODE_ALL or _group_names.is_empty():
		_last_hit_group = "ALL"
		return "ALL"

	match group_mode:
		GROUP_MODE_ALTERNATE:
			_last_hit_group = _group_names[_alternate_index % _group_names.size()]
			_alternate_index = (_alternate_index + 1) % _group_names.size()
		GROUP_MODE_RANDOM:
			var idx: int = _rng.randi_range(0, _group_names.size() - 1)
			_last_hit_group = _group_names[idx]
		_:
			_last_hit_group = _group_names[0]
	return _last_hit_group


# ============================================================
# Strobe Dispatch
# ============================================================

func _fire_strobe(group_name: String, peak: float, duration_sec: float) -> void:
	if _strobe == null or duration_sec <= 0.0:
		return

	if group_mode == GROUP_MODE_ALL or group_name == "ALL":
		if _strobe.has_method("pulse_all"):
			_strobe.call("pulse_all", peak, duration_sec)
		else:
			_strobe.pulse(peak, duration_sec)
		return

	if _strobe.has_method("pulse_group"):
		_strobe.call("pulse_group", group_name, peak, duration_sec)
	elif _strobe.has_method("pulse_one"):
		_strobe.call("pulse_one", group_name, peak, duration_sec)
	else:
		_strobe.pulse(peak, duration_sec)


# ============================================================
# Discovery / Grouping
# ============================================================

func _discover_lights() -> void:
	_lights.clear()
	_rotators.clear()
	_group_names.clear()

	var root: Node = get_node_or_null(light_root_path)
	if root == null:
		root = self

	var party_lights: Array[Node] = root.find_children("", "PartyLight", true, false)
	for node: Node in party_lights:
		_add_light_node(node, [])

	var ring_nodes: Array[Node] = root.find_children("", "RingRotator", true, false)
	for node: Node in ring_nodes:
		_add_rotator_node(node, [])

	_refresh_group_names()


func _add_light_node(node: Node, override_groups: Array[String]) -> void:
	var entry: LightEntry = LightEntry.new()
	entry.node = node
	entry.groups = _resolve_groups(node, override_groups)
	entry.has_set_energy = node.has_method("set_light_energy")
	entry.has_light_energy = _has_property(node, "light_energy")
	entry.min_energy = _get_energy_property(node, "min_energy", default_min_energy)
	entry.max_energy = _get_energy_property(node, "max_energy", default_max_energy)
	_lights.append(entry)


func _add_rotator_node(node: Node, override_groups: Array[String]) -> void:
	var entry: RotatorEntry = RotatorEntry.new()
	entry.node = node
	entry.groups = _resolve_groups(node, override_groups)
	if _has_property(node, "rotate_speed_radians"):
		entry.has_speed_property = true
		entry.speed_property = "rotate_speed_radians"
	elif _has_property(node, "ring_speed"):
		entry.has_speed_property = true
		entry.speed_property = "ring_speed"
	entry.has_set_speed = node.has_method("set_ring_speed")
	_rotators.append(entry)


func _resolve_groups(node: Node, override_groups: Array[String]) -> Array[String]:
	var groups: Array[String] = []

	if not override_groups.is_empty():
		groups = override_groups.duplicate()
	else:
		var key_name: String = node.name
		if group_overrides.has(key_name):
			groups = _as_string_array(group_overrides[key_name])
		else:
			var path_key: String = str(node.get_path())
			if group_overrides.has(path_key):
				groups = _as_string_array(group_overrides[path_key])

	if groups.is_empty():
		if _has_property(node, "light_groups"):
			var lg: Variant = node.get("light_groups")
			if lg is Array:
				groups = lg.duplicate()

	if groups.is_empty():
		var node_groups: Array = node.get_groups()
		for g: Variant in node_groups:
			if g != "":
				groups.append(str(g))

	if groups.is_empty():
		groups.append("Rig_Default")

	return groups


func _refresh_group_names() -> void:
	_group_names.clear()
	for entry: LightEntry in _lights:
		_add_group_names(entry.groups)
	for entry: RotatorEntry in _rotators:
		_add_group_names(entry.groups)


func _add_group_names(groups: Array[String]) -> void:
	for g: String in groups:
		if not _group_names.has(g):
			_group_names.append(g)


func _get_energy_property(node: Node, prop: String, fallback: float) -> float:
	if _has_property(node, prop):
		var v: Variant = node.get(prop)
		if v is float or v is int:
			return float(v)
	return fallback


func _as_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for v: Variant in value:
			result.append(str(v))
	return result


func _has_property(node: Object, prop: String) -> bool:
	for item: Dictionary in node.get_property_list():
		if item.has("name") and String(item["name"]) == prop:
			return true
	return false


func _find_analyzer() -> SpectrumAudioAnalyzer:
	var by_name := get_node_or_null("MicPlayer") as SpectrumAudioAnalyzer
	if by_name != null:
		return by_name

	var nodes: Array[Node] = get_tree().get_root().find_children("", "SpectrumAudioAnalyzer", true, false)
	if not nodes.is_empty():
		return nodes[0] as SpectrumAudioAnalyzer

	return null


func _find_osc() -> OscClockReceiver:
	var nodes: Array[Node] = get_tree().get_root().find_children("", "OscClockReceiver", true, false)
	if not nodes.is_empty():
		return nodes[0] as OscClockReceiver
	return null


# ============================================================
# How to use
# ============================================================
# 1) Add LightController as a node in your scene (sibling to lights or a parent).
# 2) Set light_root_path to the rig root (or leave "." to search below this node).
# 3) Ensure a SpectrumAudioAnalyzer exists (node name "MicPlayer" is auto-detected).
# 4) (Optional) Add OscClockReceiver for external beat sync.
# 5) Add groups to rigs/lights via Node groups or PartyLight.light_groups.
#    - Example groups: "Rig_A", "Rig_B", "Rig_C"
