extends CharacterBody3D
class_name PlayerScript

@export var speed: float = 0.0
@export var in_corner: bool = false
@export var turn_time: float = .5
@export var roll_enabled: bool = true
@export var roll_speed_deg_per_sec: float = 35.0  # constant roll rate
var _roll_angle: float = 0.0
var _base_basis: Basis
var _turning: bool = false
var current_target: Area3D = null

func _ready() -> void:
	_base_basis = global_transform.basis

func _physics_process(delta: float) -> void:
	if _turning:
		velocity = Vector3.ZERO
		_apply_roll(delta) # keep rolling while turning; remove if you want
		move_and_slide()
		return

	var forward: Vector3 = -global_transform.basis.z
	velocity = forward * speed
	move_and_slide()

	_apply_roll(delta)

func _apply_roll(delta: float) -> void:
	if not roll_enabled:
		return

	var base_basis := global_transform.basis
	var forward_axis: Vector3 = (-base_basis.z).normalized()

	var delta_roll := deg_to_rad(roll_speed_deg_per_sec) * delta

	# Apply a *small* roll step each frame (constant angular velocity)
	global_transform.basis = (Basis(forward_axis, delta_roll) * base_basis).orthonormalized()

func corner_processing(pivotController: PivotController) -> void:
	in_corner = true
	current_target = pivotController.stored_target;

	# Turn direction should be based on the corner center, not player position
	var pivot: Vector3 = pivotController.global_position
	var dir: Vector3 = (current_target.global_position - pivot).normalized()
	if dir.length() < 0.0001:
		return

	# Optional but helps a LOT: snap to pivot before turning so you stay centered
	global_position = pivot

	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD

	var target_basis: Basis = Basis().looking_at(dir, up)

	_turning = true
	var tw := create_tween()
	tw.tween_property(self, "global_transform:basis", target_basis, turn_time)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	tw.finished.connect(func() -> void:
		_turning = false
	)
	
func corner_exited(exitedPoint: Area3D)->bool:
	if exitedPoint == current_target and !_turning:
		current_target = null
		in_corner = false
		return true
	else:
		return false
		
