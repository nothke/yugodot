extends Node

@export var hoodCamera: NodePath
@export var chaseCamera: NodePath
@export var tracksideCamera: NodePath
const CAR = preload("res://car.tscn")
@export var noPostEnvironment: Environment
var sun: DirectionalLight3D
@export var countDownTimeSet = 4
var countDownTime = countDownTimeSet
var hoodCameraIsActive = false

var hasRestared = false
var players = [false, false, false, false]
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
	$CountDownTimer.start(1)
	$CountDownTimer.one_shot = false

func _input(event):

	if event is InputEventKey and event.pressed:

		if event.is_action_pressed("p1_throttle"):
			add_player(0)
		if event.is_action_pressed("p2_throttle"):
			add_player(1)
		if event.is_action_pressed("p3_throttle"):
			add_player(2)
		if event.is_action_pressed("p4_throttle"):
			add_player(3)
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

func add_player(id):
	if(players[id]|| countDownTime <=0):
		return
	players[id] = true
	var car = CAR.instantiate()
	car.playerId = id
	get_parent().add_child(car)
	var cars = get_tree().get_nodes_in_group("car_group")
	if cars.size() ==1:
		car.global_position = %CarSpawnPoint.global_position
	else:
		car.global_position =  cars[cars.size()-2].global_position
		car.global_position.x += car.get_child(0).shape.size.x * 2
	%viewport_gird.add_new_player_view(car.camera, car.ui)
	countDownTime = countDownTimeSet
	$countdown.text = str(countDownTime)


func _on_count_down_timer_timeout() -> void:
	if(countDownTime > 1):
		$audio_countdown.play()
		$countdown.text = str(countDownTime)
		countDownTime -=1
		return
	if(countDownTime ==1):
		$audio_countdown.play()
		$countdown.text = "YOU"
		countDownTime -=1
		return
	if(countDownTime == 0):
		$countdown.text = "GO"
		countDownTime -=1
		var cars = get_tree().get_nodes_in_group("car_group")
		for car in cars:
			car.start_race()
		return
	countDownTime -=1
	if(countDownTime < -1):
		$countdown.visible = false
		$CountDownTimer.stop()
