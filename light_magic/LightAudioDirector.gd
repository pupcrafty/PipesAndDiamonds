extends Node
class_name LightAudioDirector

## Light + Audio Director
##
## Drives PartyLight, PartyLightRing, and Strobe nodes using AudioServiceOSC.
## Implements the 4 non-triggered scenes: Bass Gravity, Mid Bloom, Treble Spark, Mix Madness.

enum SceneId { BASS_GRAVITY, MID_BLOOM, TREBLE_SPARK, MIX_MADNESS }

@export var osc_receiver_path: NodePath = NodePath("AudioServiceOSC")
@export var party_light_root: NodePath = NodePath(".")
@export var ring_root: NodePath
@export var strobe_path: NodePath

@export var beats_per_scene: int = 32
@export var diagnostics_enabled: bool = true
@export var diagnostics_label_path: NodePath

# Endpoints needed for the 4 non-triggered scenes
const REQUIRED_ENDPOINTS: Array[String] = [
	"/clock/beat",
	"/clock/beat_id",
	"/clock/bpm",
	"/audio/bass",
	"/audio/mid",
	"/audio/treble",
	"/audio/total_energy",
	"/audio/movement",
	"/audio/pulse",
	"/audio/band_presence_high_2",
]

# Scene multipliers (bass, mid, treble)
const WEIGHT_BASS: Vector3 = Vector3(1.5, 0.5, 0.3)
const WEIGHT_MID: Vector3 = Vector3(0.7, 1.6, 0.7)
const WEIGHT_TREBLE: Vector3 = Vector3(0.4, 0.8, 1.8)

var _osc_receiver: Node
var _party_lights: Array[Node] = []
var _rings: Array[Node] = []
var _strobe: Node

var _current_scene: SceneId = SceneId.BASS_GRAVITY
var _beats_in_scene: int = 0
var _last_beat_id: int = -1
var _ring_angle: float = 0.0

# Mix Madness assignment: [R, G, B] -> weight vectors
var _mix_weights: Array[Vector3] = []
var _diag_label: Label
var _last_energy_value: float = 0.0
var _last_z_sweep: float = 0.0
var _osc_status: String = "OSC: unknown"
var _targets_ready: bool = false
var _strobe_status: String = "Strobe: unknown"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	if diagnostics_enabled:
		_setup_diagnostics()

	_rng.randomize()

	_osc_receiver = _find_osc_receiver()
	if _osc_receiver == null:
		_osc_status = "OSC: not found (path: %s)" % str(osc_receiver_path)
	else:
		_osc_status = "OSC: connected"

	if _osc_receiver != null and _osc_receiver.has_signal("endpoint_updated"):
		_osc_receiver.endpoint_updated.connect(_on_endpoint_updated)
		if _osc_receiver.has_method("subscribe_to_endpoint"):
			for endpoint in REQUIRED_ENDPOINTS:
				_osc_receiver.subscribe_to_endpoint(endpoint)

	call_deferred("_refresh_targets")

	_set_scene(SceneId.BASS_GRAVITY)
	set_process(true)

func _process(delta: float) -> void:
	if _osc_receiver == null:
		if diagnostics_enabled:
			_update_diagnostics(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0)
		return
	if not _targets_ready:
		_refresh_targets()

	var bass: float = _osc_receiver.get_float("/audio/bass")
	var mid: float = _osc_receiver.get_float("/audio/mid")
	var treble: float = _osc_receiver.get_float("/audio/treble")
	var total_energy: float = _osc_receiver.get_float("/audio/total_energy")
	var movement: float = _osc_receiver.get_float("/audio/movement")
	var bpm: float = _osc_receiver.get_float("/clock/bpm")
	if bpm <= 0.0:
		bpm = 120.0

	var beat_id: int = _osc_receiver.get_int("/clock/beat_id")
	var pulse: bool = _osc_receiver.get_bool("/audio/pulse")
	var treble_presence: bool = _osc_receiver.get_bool("/audio/band_presence_high_2")

	_apply_scene_lighting(bass, mid, treble, total_energy, movement, beat_id)
	_apply_ring_rotation(bpm, pulse, delta)
	_apply_strobe(pulse, treble_presence)

	if diagnostics_enabled:
		_update_diagnostics(bass, mid, treble, total_energy, movement, bpm, beat_id)

func _on_endpoint_updated(endpoint_name: String, value: Variant) -> void:
	if endpoint_name == "/clock/beat":
		var beat_id: int = 0
		if value is int:
			beat_id = value
		elif value is float:
			beat_id = int(value)
		_on_beat(beat_id)

func _on_beat(beat_id: int) -> void:
	if beat_id == _last_beat_id:
		return
	_last_beat_id = beat_id
	_beats_in_scene += 1

	# Beat pulse is common for these 4 scenes
	_pulse_strobe(2.0, 0.08)

	if _beats_in_scene >= beats_per_scene:
		_beats_in_scene = 0
		_advance_scene()

func _advance_scene() -> void:
	var next_scene: int = int(_current_scene) + 1
	if next_scene > int(SceneId.MIX_MADNESS):
		next_scene = int(SceneId.BASS_GRAVITY)
	_set_scene(SceneId.values()[next_scene])

func _set_scene(scene_id: SceneId) -> void:
	_current_scene = scene_id

	if _current_scene == SceneId.MIX_MADNESS:
		_mix_weights = [WEIGHT_BASS, WEIGHT_MID, WEIGHT_TREBLE]
		_mix_weights.shuffle()

	_set_strobe_random_color()

func _apply_scene_lighting(bass: float, mid: float, treble: float, total_energy: float, movement: float, beat_id: int) -> void:
	var weight: Vector3 = _scene_weight(_current_scene)

	for light_node in _party_lights:
		if not light_node.has_method("set_light_energy"):
			continue

		var energy_value: float = (bass * weight.x) + (mid * weight.y) + (treble * weight.z)
		energy_value += movement * 0.25
		light_node.set_light_energy(energy_value)

		var z_sweep: float = 0.0
		match _current_scene:
			SceneId.BASS_GRAVITY:
				z_sweep = clamp((bass * 2.5) - 1.2, -1.0, 1.0)
			SceneId.MID_BLOOM:
				z_sweep = sin(float(beat_id) * 0.35)
			SceneId.TREBLE_SPARK:
				z_sweep = clamp((treble * 2.0) - 1.0, -1.0, 1.0)
			SceneId.MIX_MADNESS:
				z_sweep = _mix_dominant_z_sweep(bass, mid, treble, beat_id)
		light_node.set_z_sweep(z_sweep)

		# Mix Madness uses existing light colors for grouping only (no runtime color changes).

		# Capture values from the first light for diagnostics.
		if _last_energy_value == 0.0 and _last_z_sweep == 0.0:
			_last_energy_value = energy_value
			_last_z_sweep = z_sweep

func _apply_ring_rotation(bpm: float, pulse: bool, delta: float) -> void:
	if _rings.is_empty():
		return

	var speed: float = 0.25
	match _current_scene:
		SceneId.BASS_GRAVITY:
			speed = 0.15
		SceneId.MID_BLOOM:
			speed = 0.25
		SceneId.TREBLE_SPARK:
			speed = 0.40
		SceneId.MIX_MADNESS:
			speed = 0.30

	_ring_angle += (bpm / 60.0) * speed * delta
	if pulse:
		_ring_angle += 0.15

	for ring_node in _rings:
		if ring_node != null and ring_node.has_method("set_ring_rotation"):
			ring_node.set_ring_rotation(_ring_angle)

func _apply_strobe(pulse: bool, treble_presence: bool) -> void:
	if _strobe == null:
		return

	match _current_scene:
		SceneId.BASS_GRAVITY:
			# Beat pulse handled in _on_beat
			pass
		SceneId.MID_BLOOM:
			if pulse:
				_pulse_strobe(1.6, 0.06)
		SceneId.TREBLE_SPARK:
			if pulse:
				_pulse_strobe(2.0, 0.05)
		SceneId.MIX_MADNESS:
			if pulse and treble_presence:
				_pulse_strobe(1.8, 0.05)

func _pulse_strobe(peak_energy: float, duration_sec: float) -> void:
	if _strobe != null and _strobe.has_method("pulse"):
		_strobe.pulse(peak_energy, duration_sec)

func _set_strobe_random_color() -> void:
	if _strobe == null:
		return

	var options: Array[Color] = [
		Color(1.0, 0.0, 0.0), # red
		Color(0.0, 1.0, 0.0), # green
		Color(0.0, 0.0, 1.0), # blue
		Color(1.0, 1.0, 1.0), # white
	]
	var chosen: Color = options[_rng.randi_range(0, options.size() - 1)]

	for child in _strobe.get_children():
		if child is OmniLight3D:
			child.light_color = chosen

func _scene_weight(scene_id: SceneId) -> Vector3:
	match scene_id:
		SceneId.BASS_GRAVITY:
			return WEIGHT_BASS
		SceneId.MID_BLOOM:
			return WEIGHT_MID
		SceneId.TREBLE_SPARK:
			return WEIGHT_TREBLE
		SceneId.MIX_MADNESS:
			# Energy uses the average of the mixed weights; color handles per-channel weights
			return (WEIGHT_BASS + WEIGHT_MID + WEIGHT_TREBLE) / 3.0
	return WEIGHT_BASS

func _mix_color(bass: float, mid: float, treble: float) -> Color:
	if _mix_weights.size() != 3:
		return Color(1.0, 1.0, 1.0)

	var r: float = (bass * _mix_weights[0].x) + (mid * _mix_weights[0].y) + (treble * _mix_weights[0].z)
	var g: float = (bass * _mix_weights[1].x) + (mid * _mix_weights[1].y) + (treble * _mix_weights[1].z)
	var b: float = (bass * _mix_weights[2].x) + (mid * _mix_weights[2].y) + (treble * _mix_weights[2].z)

	# Normalize to 0-1 range for light color
	var max_val: float = max(r, max(g, b))
	if max_val > 1.0:
		r /= max_val
		g /= max_val
		b /= max_val

	return Color(r, g, b)

func _mix_dominant_z_sweep(bass: float, mid: float, treble: float, beat_id: int) -> float:
	if _mix_weights.size() != 3:
		return 0.0

	var r: float = (bass * _mix_weights[0].x) + (mid * _mix_weights[0].y) + (treble * _mix_weights[0].z)
	var g: float = (bass * _mix_weights[1].x) + (mid * _mix_weights[1].y) + (treble * _mix_weights[1].z)
	var b: float = (bass * _mix_weights[2].x) + (mid * _mix_weights[2].y) + (treble * _mix_weights[2].z)

	var dominant: int = 0
	var max_val: float = r
	if g > max_val:
		max_val = g
		dominant = 1
	if b > max_val:
		max_val = b
		dominant = 2

	match dominant:
		0:
			return clamp((bass * 2.5) - 1.2, -1.0, 1.0)
		1:
			return sin(float(beat_id) * 0.35)
		2:
			return clamp((treble * 2.0) - 1.0, -1.0, 1.0)

	return 0.0

func _find_party_lights() -> Array[Node]:
	if party_light_root != NodePath("."):
		var root_node: Node = get_node_or_null(party_light_root)
		if root_node != null:
			return root_node.find_children("", "PartyLight", true, false)

	return get_tree().get_root().find_children("", "PartyLight", true, false)

func _find_rings() -> Array[Node]:
	if ring_root != NodePath(""):
		var root_node: Node = get_node_or_null(ring_root)
		if root_node != null:
			var scoped_nodes: Array[Node] = root_node.find_children("", "", true, false)
			return _filter_ring_nodes(scoped_nodes)

	# Fallback: global search for class name used by PartyLightRing.gd
	var class_matches: Array[Node] = get_tree().get_root().find_children("", "RingRotator", true, false)
	if not class_matches.is_empty():
		return class_matches

	var all_nodes: Array[Node] = get_tree().get_root().find_children("", "", true, false)
	return _filter_ring_nodes(all_nodes)

func _filter_ring_nodes(nodes: Array[Node]) -> Array[Node]:
	var rings: Array[Node] = []
	for node in nodes:
		if node.has_method("set_ring_rotation"):
			rings.append(node)
	return rings

func _find_strobe() -> Node:
	if strobe_path != NodePath(""):
		var direct: Node = get_node_or_null(strobe_path)
		if direct != null:
			return direct
	# Fallback: search by class name or method
	var candidates: Array[Node] = get_tree().get_root().find_children("", "StrobeController", true, false)
	if not candidates.is_empty():
		return candidates[0]
	var all_nodes: Array[Node] = get_tree().get_root().find_children("", "", true, false)
	for node in all_nodes:
		if node.has_method("pulse"):
			return node
	return null

func _find_osc_receiver() -> Node:
	if osc_receiver_path != NodePath(""):
		var direct: Node = get_node_or_null(osc_receiver_path)
		if direct != null:
			return direct
	# Fallback: search by common node name
	var candidates: Array[Node] = get_tree().get_root().find_children("AudioServiceOSC", "", true, false)
	return candidates[0] if not candidates.is_empty() else null

func _refresh_targets() -> void:
	_rings = _find_rings()
	_strobe = _find_strobe()
	_party_lights = _find_party_lights()
	_targets_ready = not _party_lights.is_empty()
	_strobe_status = "Strobe: connected" if _strobe != null else "Strobe: not found"

func _setup_diagnostics() -> void:
	if diagnostics_label_path != NodePath(""):
		_diag_label = get_node_or_null(diagnostics_label_path) as Label
		if _diag_label != null:
			return

	var canvas := CanvasLayer.new()
	canvas.name = "LightAudioDiagnostics"
	add_child(canvas)

	var label := Label.new()
	label.name = "DiagnosticsLabel"
	label.position = Vector2(16, 16)
	label.size = Vector2(520, 240)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Light Audio Diagnostics"
	canvas.add_child(label)
	_diag_label = label

func _update_diagnostics(
	bass: float,
	mid: float,
	treble: float,
	total_energy: float,
	movement: float,
	bpm: float,
	beat_id: int
) -> void:
	if _diag_label == null:
		return

	var scene_name := _scene_name(_current_scene)
	var light_count: int = _party_lights.size()
	var ring_count: int = _rings.size()
	var strobe_present: bool = _strobe != null

	var info := ""
	info += "%s\n" % _osc_status
	info += "%s\n" % _strobe_status
	info += "Scene: %s\n" % scene_name
	info += "Lights: %d | Rings: %d | Strobe: %s\n" % [light_count, ring_count, str(strobe_present)]
	info += "BPM: %.1f | Beat ID: %d\n" % [bpm, beat_id]
	info += "Bass/Mid/Treble: %.2f / %.2f / %.2f\n" % [bass, mid, treble]
	info += "Total Energy: %.2f | Movement: %.2f\n" % [total_energy, movement]
	info += "Applied -> PartyLight.set_light_energy: %.2f\n" % _last_energy_value
	info += "Applied -> PartyLight.set_z_sweep: %.2f\n" % _last_z_sweep
	info += "Ring rotation -> PartyLightRing.set_ring_rotation (shared angle)\n"
	info += "Strobe -> Strobe.pulse on beat/pulse\n"

	_diag_label.text = info

func _scene_name(scene_id: SceneId) -> String:
	match scene_id:
		SceneId.BASS_GRAVITY:
			return "Bass Gravity"
		SceneId.MID_BLOOM:
			return "Mid Bloom"
		SceneId.TREBLE_SPARK:
			return "Treble Spark"
		SceneId.MIX_MADNESS:
			return "Mix Madness"
	return "Unknown"
