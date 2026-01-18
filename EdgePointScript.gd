extends Area3D

@export var player_path: NodePath

@onready var player: Node = get_node_or_null(player_path)

 


func _ready() -> void:
	monitoring = true

func _on_body_entered(body: Node3D) -> void:
	if body.name == "ChaseHeart":
		print("Heart Entered")
		var heart :=body as ChaseHeart
		if heart.in_corner:
			return
		
		var parent = self.get_parent_node_3d();
			
		var siblings: Array[Area3D] = []
		var pivot: PivotPoint = null
		for child in parent.get_children():
			if child != self and child is Area3D :
				if child.name != "PivotPoint":
					siblings.append(child)
				else:
					pivot = child as PivotPoint
		var target: Area3D = siblings.pick_random()			
		heart.corner_processing(target, parent)
		pivot.store_target(target)
	elif body.name == "Player":
		var parent = self.get_parent();
		var pivot: PivotPoint = parent.get_node("PivotPoint") as PivotPoint
		#player.cornerProcessing(pivot.stored_target, parent)
		

	# Call the player's handler and pass *this corner*

func _on_body_exited(body: Node3D) -> void:	
	if body.name == "Player":
		body.corner_exited(self)
