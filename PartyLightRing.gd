extends Node3D
class_name RingRotator

@export var rotate_speed_radians: float = 1 # radians/sec

var ring_angle: float = 0.0
var _base_position: Vector3
var _base_basis: Basis
var _z_tween: Tween

func _ready() -> void:
	_base_position = position
	_base_basis = basis


# Sets the ring's rotation about its own center (local Y axis)
func set_ring_rotation(angle_radians: float) -> void:
	# Rotate around the ring's local UP axis.
	# This keeps it spinning even if the whole rig is rotated in the world.
	basis = Basis(transform.basis.z.normalized(), angle_radians)

func pulse_z(offset: float, out_time: float, return_time: float) -> void:
	if _z_tween != null and _z_tween.is_running():
		_z_tween.kill()

	var axis: Vector3 = _base_basis.z.normalized()
	var target_position: Vector3 = _base_position + (axis * offset)

	_z_tween = create_tween()
	_z_tween.tween_property(self, "position", target_position, out_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_z_tween.tween_property(self, "position", _base_position, return_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
