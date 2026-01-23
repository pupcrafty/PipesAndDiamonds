extends Node3D
class_name RingRotator

@export var rotate_speed_radians: float = 1 # radians/sec

var ring_angle: float = 0.0

func _ready() -> void:
	pass


# Sets the ring's rotation about its own center (local Y axis)
func set_ring_rotation(angle_radians: float) -> void:
	# Rotate around the ring's local UP axis.
	# This keeps it spinning even if the whole rig is rotated in the world.
	basis = Basis(transform.basis.z.normalized(), angle_radians)
