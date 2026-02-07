extends SpotLight3D
class_name PartyLight

@export var min_energy: float = 0.0
@export var max_energy: float = 10.0
@export var light_groups: Array[String] = []

func set_light_energy(energy:float)-> void:
	energy = clamp(energy, min_energy, max_energy)
	self.light_energy = energy
