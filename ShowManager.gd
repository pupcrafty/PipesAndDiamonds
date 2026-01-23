extends Node
class_name ShowManager

signal routine_changed(routine_name: String)

@export var light_root_path: NodePath = NodePath("..")
@export var strobe_path: NodePath = NodePath("Strobe")
@export var initial_routine: String = "Warm Wash"

var _routines: Array[Dictionary] = []
var _current_index: int = 0
var _current: Dictionary = {}

var _lights: Array[PartyLight] = []
var _rings: Array[RingRotator] = []
var _strobe: StrobeController

var _time: float = 0.0
var _ring_angle: float = 0.0
var _strobe_timer: float = 0.0
var _strobe_waiting: bool = true

const GROUP_BASE_COLORS := {
	"Red": Color(1.0, 0.15, 0.15),
	"Green": Color(0.2, 1.0, 0.25),
	"Blue": Color(0.2, 0.45, 1.0)
}


func _ready() -> void:
	_build_routines()
	_collect_nodes()

	if !_set_routine_by_name(initial_routine):
		_set_routine_by_index(0)


func _process(delta: float) -> void:
	if _current.is_empty():
		return

	_time += delta
	_update_rings(delta)
	_update_sweep()
	_update_dynamic_colors()
	_update_strobe(delta)


func next_routine() -> void:
	_set_routine_by_index((_current_index + 1) % _routines.size())


func previous_routine() -> void:
	var next_index := _current_index - 1
	if next_index < 0:
		next_index = _routines.size() - 1
	_set_routine_by_index(next_index)


func set_routine_by_name(name: String) -> void:
	_set_routine_by_name(name)


func get_current_routine_name() -> String:
	return _current.get("name", "")


func _build_routines() -> void:
	_routines = [
		{
			"name": "Warm Wash",
			"ring_speed": 0.35,
			"energy": 2.8,
			"color_mode": "warm",
			"sweep_speed": 0.2,
			"strobe": false
		},
		{
			"name": "Cool Spin",
			"ring_speed": 1.0,
			"energy": 3.6,
			"color_mode": "cool",
			"sweep_speed": 0.7,
			"strobe": false
		},
		{
			"name": "RGB Pulse",
			"ring_speed": 0.6,
			"energy": 4.2,
			"color_mode": "pulse",
			"pulse_speed": 2.0,
			"sweep_speed": 0.5,
			"strobe": false
		},
		{
			"name": "Rainbow Chase",
			"ring_speed": 1.4,
			"energy": 4.6,
			"color_mode": "rainbow",
			"rainbow_speed": 0.35,
			"sweep_speed": 1.0,
			"strobe": false
		},
		{
			"name": "Strobe Hits",
			"ring_speed": 0.25,
			"energy": 2.4,
			"color_mode": "white",
			"sweep_speed": 0.1,
			"strobe": true,
			"strobe_frequency": 10.0,
			"strobe_on": 0.5,
			"strobe_off": 1.0
		}
	]


func _collect_nodes() -> void:
	_lights.clear()
	_rings.clear()
	_strobe = null

	var root := get_node_or_null(light_root_path)
	if root == null:
		root = get_parent()
	if root == null:
		push_warning("ShowManager: Unable to find light root.")
		return

	var stack: Array[Node] = [root]
	while !stack.is_empty():
		var node := stack.pop_back()
		if node is PartyLight:
			_lights.append(node)
		elif node is RingRotator:
			_rings.append(node)

		for child in node.get_children():
			if child is Node:
				stack.append(child)

	_strobe = root.get_node_or_null(strobe_path) as StrobeController


func _set_routine_by_index(index: int) -> void:
	if _routines.is_empty():
		return
	_current_index = clampi(index, 0, _routines.size() - 1)
	_current = _routines[_current_index]
	_apply_routine()


func _set_routine_by_name(name: String) -> bool:
	for i in _routines.size():
		if _routines[i].get("name", "") == name:
			_set_routine_by_index(i)
			return true
	return false


func _apply_routine() -> void:
	_ring_angle = 0.0
	_time = 0.0
	_strobe_timer = 0.0
	_strobe_waiting = true

	var energy := float(_current.get("energy", 3.0))
	for light in _lights:
		light.set_light_energy(energy)
		if !_is_dynamic_color_mode():
			light.light_color = _color_for_light(light)

	if _strobe != null and !_current.get("strobe", false):
		_strobe.stop_strobe()

	routine_changed.emit(_current.get("name", ""))


func _update_rings(delta: float) -> void:
	var speed := float(_current.get("ring_speed", 0.0))
	if speed == 0.0:
		return
	_ring_angle = fmod(_ring_angle + speed * delta, TAU)

	for i in _rings.size():
		var offset := (TAU / maxf(1.0, float(_rings.size()))) * float(i)
		_rings[i].set_ring_rotation(_ring_angle + offset)


func _update_sweep() -> void:
	var sweep_speed := float(_current.get("sweep_speed", 0.0))
	if sweep_speed == 0.0:
		return

	for i in _lights.size():
		var phase := _time * sweep_speed + float(i) * 0.4
		_lights[i].set_z_sweep(sin(phase))


func _update_dynamic_colors() -> void:
	if !_is_dynamic_color_mode():
		return

	var mode := String(_current.get("color_mode", ""))
	match mode:
		"pulse":
			var pulse_speed := float(_current.get("pulse_speed", 1.5))
			var pulse := 0.5 + 0.5 * sin(_time * pulse_speed)
			for light in _lights:
				var base := _color_for_light(light)
				light.light_color = base.lerp(Color.WHITE, pulse * 0.4)
		"rainbow":
			var rainbow_speed := float(_current.get("rainbow_speed", 0.3))
			for i in _lights.size():
				var hue := fmod(_time * rainbow_speed + float(i) * 0.12, 1.0)
				_lights[i].light_color = Color.from_hsv(hue, 0.8, 1.0)


func _update_strobe(delta: float) -> void:
	if _strobe == null or !_current.get("strobe", false):
		return

	_strobe_timer -= delta
	if _strobe_timer > 0.0:
		return

	var on_duration := float(_current.get("strobe_on", 0.5))
	var off_duration := float(_current.get("strobe_off", 1.0))
	var frequency := float(_current.get("strobe_frequency", 10.0))

	if _strobe_waiting:
		_strobe.start_strobe(frequency, on_duration)
		_strobe_timer = on_duration
		_strobe_waiting = false
	else:
		_strobe_timer = off_duration
		_strobe_waiting = true


func _is_dynamic_color_mode() -> bool:
	var mode := String(_current.get("color_mode", ""))
	return mode == "pulse" or mode == "rainbow"


func _color_for_light(light: PartyLight) -> Color:
	var mode := String(_current.get("color_mode", "warm"))
	if mode == "white":
		return Color(1.0, 1.0, 1.0)

	var base_color := _base_color_from_groups(light.light_groups)

	match mode:
		"warm":
			return base_color.lerp(Color(1.0, 0.55, 0.25), 0.7)
		"cool":
			return base_color.lerp(Color(0.2, 0.6, 1.0), 0.7)
		_:
			return base_color


func _base_color_from_groups(groups: Array[String]) -> Color:
	for group_name in groups:
		if GROUP_BASE_COLORS.has(group_name):
			return GROUP_BASE_COLORS[group_name]
	return Color(1.0, 1.0, 1.0)
