extends Area3D

signal checkpoint_entered(body, id)


func _on_body_entered(body: Node3D) -> void:
	var id = name.split("Checkpoint")[1]
	if id == null:
		return
	checkpoint_entered.emit(body, int(id))
