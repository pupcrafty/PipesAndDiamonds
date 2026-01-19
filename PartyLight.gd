extends SpotLight3D
class_name PartyLight

var outward_push: float = 0.0
var circular_rotation: float = 0;
var rotation_orientation: float =1.0;
var base_angle_x: float =0;
var base_angle_y: float =0;
var base_angle_z: float =0;
var ring_index: int = 0
var z_push_scale: float = 0.14

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	refresh_base_state()



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_intensity_changed(new_energy: float) -> void:
	light_energy = new_energy

func _on_outward_push_change(new_outward_push: float) -> void:
	outward_push = new_outward_push
	update_local_rotation()
	
func _on_circular_rotation_change(new_circular_rotation_change: float)-> void:
	circular_rotation = new_circular_rotation_change
	update_local_rotation()
	
	
func update_local_rotation()->void:
	var theta: float = deg_to_rad(circular_rotation) * rotation_orientation
	var radius: float = get_base_distance_from_focus()

	var x_offset: float = radius * cos(theta)
	var y_offset: float = radius * sin(theta)
	var z_offset: float = outward_push * z_push_scale

	rotation = Vector3(
		base_angle_x + x_offset,
		base_angle_y + y_offset,
		base_angle_z + z_offset
	)

func set_rotation_orientation(orientation: float):
	rotation_orientation = orientation

func set_ring_index(index: int) -> void:
	ring_index = index

func get_ring_index() -> int:
	return ring_index
	
func get_base_distance_from_focus()->float:
	#normalize Y
	var y_val = self.base_angle_y
	if self.base_angle_y>180:
		y_val = self.base_angle_y -360
	return sqrt(self.base_angle_x*self.base_angle_x+y_val*y_val) 

func refresh_base_state() -> void:
	base_angle_x = rotation.x
	base_angle_y = rotation.y
	base_angle_z = rotation.z
