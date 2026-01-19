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

@export var lights_per_circle: int = 6
@export var base_angle_offset_deg: float = 0.0
@export var circle_radii: PackedFloat32Array = PackedFloat32Array([0.16, 0.24, 0.32])
@export var circle_z_tilts_deg: PackedFloat32Array = PackedFloat32Array([-6.0, 0.0, 6.0])

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

	_layout_lights(lights)
	
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

func _layout_lights(lights: Array[PartyLight]) -> void:
	if lights.is_empty():
		return

	var circle_count := circle_radii.size()
	if circle_count == 0:
		return

	var expected := lights_per_circle * circle_count
	if lights.size() != expected:
		push_warning(
			"PartyLightColorRig: expected %d lights (%d circles * %d per circle), found %d."
			% [expected, circle_count, lights_per_circle, lights.size()]
		)

	var angle_offset := deg_to_rad(base_angle_offset_deg)
	var angle_step := TAU / float(lights_per_circle)

	for i in range(lights.size()):
		var circle_index := min(i / lights_per_circle, circle_count - 1)
		var light_index := i % lights_per_circle
		var radius := circle_radii[circle_index]
		var tilt_deg := circle_z_tilts_deg.size() > circle_index ? circle_z_tilts_deg[circle_index] : 0.0

		var theta := angle_step * light_index + angle_offset
		var base_x := radius * cos(theta)
		var base_y := radius * sin(theta)
		var base_z := deg_to_rad(tilt_deg)

		var light := lights[i]
		light.rotation = Vector3(base_x, base_y, base_z)
		light.sync_base_angles()
		light.update_orbit_position()


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
