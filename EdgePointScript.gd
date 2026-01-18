extends Area3D

@export var player_path: NodePath

@onready var player: Node = get_node_or_null(player_path)

 


func _ready() -> void:
	monitoring = true

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player" and body.name != "ChaseHeart":
		return
	var player :=body as PlayerScript
	if player.in_corner:
		return
	
	var parent = self.get_parent_node_3d();
		
	var siblings: Array[Area3D] = []
	for child in parent.get_children():
		if child != self and child is Area3D and child.name != "PivotPoint":
			siblings.append(child)

	
	player.corner_processing(siblings.pick_random(), parent)
	
	
		

	# Call the player's handler and pass *this corner*

func _on_body_exited(body: Node3D) -> void:	
	if body.name == "Player":
		body.corner_exited(self)
