extends Node3D
class_name PartyLightColorRig

signal intensity_changed(new_energy: float)
signal outward_push(new_outward_push: float)
signal circular_rotation(new_rotation: float)

@export var rig_intensity: float = 1
@export var rig_outward_push: float = 0
@export var rig_rotation: float =0         # faster

@export var lights_per_ring: int = 6
@export var ring_radius: float = 0.6
@export var ring_z_offsets: Array[float] = [0.25, 0.0, -0.25]
@export var ring_phase_offset_deg: float = 0.0

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

	_layout_rings(lights)
	
	for light in lights:
		var ring_index := light.get_ring_index()
		var light_orientation: float = 1.0
		if ring_index == 1:
			light_orientation = -1.0
		light.set_rotation_orientation(light_orientation)
		
	# Push initial values into the rig + children
	_emit_all()

func _layout_rings(lights: Array[PartyLight]) -> void:
	var ring_count := ring_z_offsets.size()
	if ring_count == 0:
		return
	if lights_per_ring <= 0:
		return

	var expected := ring_count * lights_per_ring
	if lights.size() < expected:
		push_warning("PartyLightColorRig: Not enough lights for ring layout. Expected %d, found %d." % [expected, lights.size()])

	var angle_step := TAU / float(lights_per_ring)
	var base_offset := deg_to_rad(ring_phase_offset_deg)
	for ring_index in range(ring_count):
		var z_offset := ring_z_offsets[ring_index]
		for light_index in range(lights_per_ring):
			var idx := ring_index * lights_per_ring + light_index
			if idx >= lights.size():
				return
			var angle := base_offset + angle_step * float(light_index)
			var direction := Vector3(cos(angle), sin(angle), z_offset).normalized()
			var light := lights[idx]
			var basis := Basis().looking_at(direction, Vector3.UP)
			light.transform = Transform3D(basis, direction * ring_radius)
			light.set_ring_index(ring_index)
			light.refresh_base_state()


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
