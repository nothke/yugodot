extends Node

@export var hoodCamera: NodePath
@export var chaseCamera: NodePath
@export var tracksideCamera: NodePath

@export var noPostEnvironment: Environment

var sun: DirectionalLight3D

var hoodCameraIsActive = false

var hasRestared = false

func _ready():
	#get_node(chaseCamera).make_current()

	sun = get_node("../sun") as DirectionalLight3D
	assert(sun != null)

	var enviro := get_node("../WorldEnvironment") as WorldEnvironment

	var config := ConfigFile.new()
	var configPath = "config.ini"
	if config.load(configPath) == OK:
		var cfgBool = func(segment, entry):
			return float(config.get_value(segment, entry, 1)) != 0

		sun.shadow_enabled = cfgBool.call("graphics", "shadows")

		var noPost : bool = !cfgBool.call("graphics", "post_processing")

		if noPost:
			enviro.environment = noPostEnvironment

func _input(event):

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
			hasRestared = true

		if event.keycode == KEY_C:
			hoodCameraIsActive = not hoodCameraIsActive

			if hoodCameraIsActive:
				(get_node(hoodCamera) as Camera3D).make_current()
			else:
				(get_node(chaseCamera) as Camera3D).make_current()

		if event.keycode == KEY_V:
			(get_node(tracksideCamera)).make_current()
