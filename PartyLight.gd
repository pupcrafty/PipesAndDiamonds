extends SpotLight3D
class_name PartyLight

@export var sweep_speed: float = 0.5
@export var min_energy: float = 0.0
@export var max_energy: float = 6.0
@export var light_groups: Array[String] = []

var t: float = 0.0

var base_basis: Basis
var forward_basis: Basis
var back_basis: Basis

func _ready() -> void:
	# Store the authored starting orientation (local)
	base_basis = global_transform.basis

	# Godot "forward" direction is -Z.
	# We want the LIGHT to point along world -Z (forward) or +Z (back).
	# Since a SpotLight points along its local -Z, we set basis so that -Z aligns with desired direction.
	forward_basis = Basis.looking_at(-Vector3.FORWARD, Vector3.UP) # points along world -Z
	back_basis    = Basis.looking_at(Vector3.FORWARD,  Vector3.UP) # points along world +Z

## value ∈ [-1, 1]
##  1  -> world forward (-Z)
##  0  -> authored starting rotation
## -1  -> world back (+Z)
func set_z_sweep(value: float) -> void:
	value = clamp(value, -1.0, 1.0)

	var qb := Quaternion(base_basis)
	var qf := Quaternion(forward_basis)
	var qk := Quaternion(back_basis)

	var q: Quaternion
	if value >= 0.0:
		# 0..1 : base -> forward
		q = qb.slerp(qf, value)
	else:
		# -1..0 : back -> base
		q = qk.slerp(qb, value + 1.0)

	var gt := global_transform
	gt.basis = Basis(q)
	global_transform = gt

func set_light_energy(energy:float)-> void:
	energy = clamp(energy, min_energy, max_energy)
	self.light_energy = energy
