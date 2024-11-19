extends GridContainer
const PLAYER_VIEW_PORT = preload("res://player_view_port.tscn")
#@onready var viewport1: SubViewport = $PlayerViewPort/SubViewPort
#@onready var viewport2: SubViewport = $PlayerViewPort/SubViewport
#@onready var Camera1: Camera3D = get_node("../car/chase_camera")
#@onready var Camera2: Camera3D = get_node("../car2/chase_camera")


#func _ready():
	#var Camera_rid1 = Camera1.get_camera_rid()
	#var viewport_rid1 = viewport1.get_viewport_rid()
	#RenderingServer.viewport_attach_camera(viewport_rid1, Camera_rid1)

func add_new_player_view(camera: Camera3D, canvas: CanvasLayer):
	var newViewPort = PLAYER_VIEW_PORT.instantiate()
	add_child(newViewPort)

	var Camera_rid = camera.get_camera_rid()
	var viewport_rid = newViewPort.get_child(0).get_viewport_rid()
	#canvas.
	RenderingServer.viewport_attach_camera(viewport_rid, Camera_rid)
	RenderingServer.viewport_attach_canvas(viewport_rid, canvas.get_canvas())

	if get_tree().get_nodes_in_group("car_group").size() > 1:
		columns = 2
