extends CSGSphere3D

@export var osc_receiver_path: NodePath = NodePath("AudioServiceListener/AudioServiceOSC")
@export var strong_energy_threshold: float = 1.2
@export var spin_start_speed_deg_per_sec: float = 360.0
@export var spin_stop_time_sec: float = 0.5
@export var spin_axis: Vector3 = Vector3.UP

var _osc_receiver: Node
var _current_speed_deg_per_sec: float = 0.0
var _armed: bool = true

func _ready() -> void:
	_osc_receiver = get_node_or_null(osc_receiver_path)

func _process(delta: float) -> void:
	var total_energy: float = 0.0
	if _osc_receiver == null:
		_osc_receiver = get_node_or_null(osc_receiver_path)
	if _osc_receiver != null and _osc_receiver.has_method("get_float"):
		total_energy = _osc_receiver.get_float("/audio/total_energy")

	# Trigger a fast spin on a strong energy edge, then decay to a stop.
	if _armed and total_energy > strong_energy_threshold:
		_current_speed_deg_per_sec = spin_start_speed_deg_per_sec
		_armed = false
	elif total_energy <= strong_energy_threshold:
		_armed = true

	var t: float = 1.0 - exp(-delta / maxf(spin_stop_time_sec, 0.0001))
	_current_speed_deg_per_sec = lerpf(_current_speed_deg_per_sec, 0.0, t)

	if _current_speed_deg_per_sec > 0.001:
		rotate(spin_axis.normalized(), deg_to_rad(_current_speed_deg_per_sec) * delta)
