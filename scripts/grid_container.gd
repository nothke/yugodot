extends GridContainer

@onready var viewport1: SubViewport = $viewport_p1/SubViewport
@onready var viewport2: SubViewport = $viewport_p2/SubViewport
@onready var Camera1: Camera3D = %chase_camera
@onready var Camera2: Camera3D = %chase_camera2


func _ready():
	var Camera_rid1 = Camera1.get_camera_rid()
	var Camera_rid2 = Camera2.get_camera_rid()
	var viewport_rid1 = viewport1.get_viewport_rid()
	var viewport_rid2 = viewport2.get_viewport_rid()
	RenderingServer.viewport_attach_camera(viewport_rid1, Camera_rid1)
	RenderingServer.viewport_attach_camera(viewport_rid2, Camera_rid2)
