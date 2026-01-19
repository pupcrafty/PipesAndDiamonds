extends Node3D
class_name PivotController

@export var stored_target: Area3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func store_target(target: Area3D) -> void:
	print("Storing direction", target.name)
	stored_target = target

func release_target() -> void:
	stored_target = null
	
