extends OmniLight3D
class_name StrobeLight

var _base_energy: float = 0.0


func _ready() -> void:
	# Remember whatever energy you set in the inspector as the "normal" value
	_base_energy = light_energy


func set_strobe_energy(e: float) -> void:
	light_energy = e


func restore_energy() -> void:
	light_energy = _base_energy
