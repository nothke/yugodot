extends Node

export var hoodCamera: NodePath
export var chaseCamera: NodePath
export var tracksideCamera: NodePath

var hoodCameraIsActive = false

var hasRestared = false

func _ready():
	get_node(chaseCamera).make_current()

func _input(event):
	
	if event is InputEventKey and event.pressed:
		
		if event.scancode == KEY_R:
			get_tree().reload_current_scene()
			hasRestared = true
			
		if event.scancode == KEY_C:
			hoodCameraIsActive = not hoodCameraIsActive
			
			if hoodCameraIsActive:
				(get_node(hoodCamera) as Camera).make_current()
			else:
				(get_node(chaseCamera) as Camera).make_current()

		if event.scancode == KEY_V:
			(get_node(tracksideCamera)).make_current()