extends Camera3D

@export var car_path: NodePath

var car: Node3D

var camPos: Vector3
var carPos: Vector3

var startSmoothing = 1.0
var raceSmoothing = 7.0
var height = 3.0
var distance = 6.0

func _ready():
	car = get_node(car_path)
	camPos = position
	
	var config = ConfigFile.new()
	var CONFIG_PATH = "config.ini"
	
	if(config.load(CONFIG_PATH) == OK):
		raceSmoothing = float(config.get_value("camera", "smoothing_rate", 7))
		height = float(config.get_value("camera", "height", 3))
		distance = float(config.get_value("camera", "distance", 6))
	else:
		print("Couldn't load" + CONFIG_PATH)

func _physics_process(dt):
	var carForward = car.transform.basis.z
	carPos = car.position
	
	var rearTargetPoint = carPos - carForward * distance
	rearTargetPoint.y = carPos.y + height
	
	var smoothing = raceSmoothing if car.race_started() else startSmoothing
	
	camPos = camPos.lerp(rearTargetPoint, dt * smoothing)
	
func _process(_delta):
	position = camPos
	look_at(carPos, Vector3.UP)
