extends Node3D
class_name PartyLightColorRig

signal intensity_changed(new_energy: float)
signal outward_push(new_outward_push: float)
signal circular_rotation(new_rotation: float)

@export var rig_intensity: float = 1
@export var rig_outward_push: float = 0
@export var rig_rotation: float =0         # faster

@export var push_min: float = 0.0
@export var push_max: float = 2.0   

@export var intensity_min: float = 0
@export var intentity_max: float = 5          # cone radius in degrees

# If you want “clockwise” to feel like increasing UI rotation, flip this
@export var clockwise_is_positive: bool = true



func _ready() -> void:
	# Connect all child SpotLights automatically
	
	var lights: Array[PartyLight]
	for child in get_children():
		if child is PartyLight:
			intensity_changed.connect(child._on_intensity_changed)
			outward_push.connect(child._on_outward_push_change)
			circular_rotation.connect(child._on_circular_rotation_change)
			lights.append(child)
	
	lights.sort_custom(func(a,b):
		return a.get_base_distance_from_focus() < b.get_base_distance_from_focus())		
	
	var light_orientation:float = 1
	var last_distance: float = -1.0
	var distance_epsilon: float = 0.0001
	
	for light in lights:
		var distance = light.get_base_distance_from_focus()
		if last_distance < 0.0 or abs(distance - last_distance) > distance_epsilon:
			if last_distance >= 0.0:
				light_orientation *= -1
			last_distance = distance
		light.set_rotation_orientation(light_orientation)
		
	# Push initial values into the rig + children
	_emit_all()


func update(rig_push_delta, rig_rotation_delta, rig_intensity_delta)->void:
	rig_outward_push = rig_outward_push+rig_push_delta
	if rig_outward_push > push_max:
		rig_outward_push = push_max
	if rig_outward_push < push_min:
		rig_outward_push = push_min
	
	rig_rotation = rig_rotation + rig_rotation_delta
	if rig_rotation > 180:
		rig_rotation = rig_rotation - 360
	if rig_rotation < -180:
		rig_rotation = 360 + rig_rotation
		
	rig_intensity = rig_intensity+rig_intensity_delta
	if rig_intensity > intentity_max:
		rig_intensity = intentity_max
	if rig_intensity < intensity_min:
		rig_intensity = intensity_min
	
	_emit_all()

func _emit_all() -> void:
	intensity_changed.emit(rig_intensity)
	outward_push.emit(rig_outward_push)
	circular_rotation.emit(rig_rotation)
