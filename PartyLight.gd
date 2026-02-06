extends SpotLight3D
class_name PartyLight

@export var sweep_speed: float = 0.5
@export var min_energy: float = 0.0
@export var max_energy: float = 6.0
@export var sweep_max_degrees: float = 50.0
@export var light_groups: Array[String] = []

var t: float = 0.0

var base_basis: Basis

func _ready() -> void:
	# Store the authored starting orientation (local)
	base_basis = global_transform.basis

## value ∈ [-1, 1]
##  1  -> world forward (-Z)
##  0  -> authored starting rotation
## -1  -> world back (+Z)
func set_z_sweep(value: float) -> void:
	value = clamp(value, -1.0, 1.0)

	var angle: float = deg_to_rad(sweep_max_degrees) * value
	var gt := global_transform
	gt.basis = base_basis.rotated(Vector3.UP, angle)
	global_transform = gt

func set_light_energy(energy:float)-> void:
	energy = clamp(energy, min_energy, max_energy)
	self.light_energy = energy
