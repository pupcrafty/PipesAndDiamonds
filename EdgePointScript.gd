extends Area3D

@export var player_path: NodePath

@onready var player: Node = get_node_or_null(player_path)

 


func _ready() -> void:
	monitoring = true

func _on_body_entered(body: Node3D) -> void:
	if body.name == "ChaseHeart":
		var heart :=body as ChaseHeart
		if heart.in_corner:
			return
		
		var parent = self.get_parent() as PivotController;
			
		var siblings: Array[Area3D] = []
		var pivot: Area3D = null
		for child in parent.get_children():
			if child != self and child is Area3D :
				if child.name != "PivotPoint":
					siblings.append(child)
		var target: Area3D = siblings.pick_random()			
		heart.corner_processing(target, parent)
		if parent.stored_target == null:
			parent.store_target(target)
	elif body.name == "Player":
		var player := body as PlayerScript
		if player.in_corner:
			return
		var parent = self.get_parent() as PivotController;
		player.corner_processing(parent)
		

	# Call the player's handler and pass *this corner*

func _on_body_exited(body: Node3D) -> void:	
	if body.name == "Player":
		var goodExit: bool = body.corner_exited(self)
		if goodExit:
			var parent = self.get_parent() as PivotController;
			parent.release_target()
	elif body.name == "ChaseHeart":
		body.corner_exited(self)
