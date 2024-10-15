extends RigidBody

export var raycastHeightOffset: float = 0

export var springRate: float = 20
export var dampRate = 2
export(float, EXP) var tractionEase: float = 2
export var maxSpeedKmh: float = 60
export(float, EXP) var sidewaysTractionEase: float = 1
export var maxTraction: float = 30
export var tractionForceMult: float = 10
export var sidewaysTractionMult: float = 1

export var engineAudioPath: NodePath
export var timingPath: NodePath 
export var  countdownPath: NodePath 

export var checkpointSoundPath: NodePath 
export var countdownSoundPath: NodePath 
export var finishSoundPath: NodePath 

export var material: Material 
export var bodyNode: NodePath 

var checkpointSound: AudioStreamPlayer 
var countdownSound: AudioStreamPlayer 
var finishSound: AudioStreamPlayer 

var engineAudio: AudioStreamPlayer3D

var torqueMult: float = 10


var wheelBase: float = 1.05
var wheelTrack: float = 0.7

var wheelRoot: Spatial

var smoothThrottle: float

var checkpointPassed: int = -1

var timingText: RichTextLabel
var countdownText: RichTextLabel

var countdown: float = 4

var sceneStartTime: float

const CHECKPOINT_NUM: int = 13
var bestTime: float
# TODO: Init capacity to CHECKPOINT_NUM
var bestCheckpointTimes = [PoolRealArray()] 
var checkpointTimes = [PoolRealArray()] 
var prevBestCheckpointTimes = [PoolRealArray()]

const red = Color(1.0, 0.0, 0.0)
const blue = Color(0, 0.0, 1.0)
const green = Color(0.0, 1.0, 0.0)
const darkGreen = Color(0.0, 0.9, 0.0)
const black = Color(0, 0, 0)


var prevYInput: float

var  config: ConfigFile
var drawParticles = true
var drawLines = false
var debugSplits = false

class Wheel:
	var point: Vector3
	var graphical: Spatial
	var dirt: Particles
	var wasGrounded: bool


var wheels = [] # Wheel

var stageEnded = false;

func race_started():
	return stageTime > 0

var stageTime: float

var speedPitch: float

var smoothSteer: float
var lastCountdownTime: int

const dbToVolume = 8.685

class ReplaySample:
	var t: Transform
	var time: float
	var throttle: float

var samples = [] # TODO: Init capacity..?

const rayLength = 0.6

func _ready():
	for i in 4:
		wheels.append(Wheel.new())
	
	wheels[0].point = Vector3(-wheelTrack, 0, wheelBase)
	wheels[1].point = Vector3(wheelTrack, 0, wheelBase)
	wheels[2].point = Vector3(-wheelTrack, 0, -wheelBase)
	wheels[3].point = Vector3(wheelTrack, 0, -wheelBase)

	# line = get_node("wheel_debug") as LineDrawer3D

	wheels[0].graphical = get_node("car/RootNode/fl") as MeshInstance
	wheels[1].graphical = get_node("car/RootNode/fr") as MeshInstance
	wheels[2].graphical = get_node("car/RootNode/rl") as MeshInstance
	wheels[3].graphical = get_node("car/RootNode/rr") as MeshInstance
	wheelRoot = wheels[0].graphical.get_parent() as Spatial

	wheels[0].dirt = get_node("dirt_fl") as Particles
	wheels[1].dirt = get_node("dirt_fr") as Particles
	wheels[2].dirt = get_node("dirt_rl") as Particles
	wheels[3].dirt = get_node("dirt_rr") as Particles

	engineAudio = get_node(engineAudioPath) as AudioStreamPlayer3D
	timingText = get_node(timingPath) as RichTextLabel
	countdownText = get_node(countdownPath) as RichTextLabel

	sceneStartTime = OS.get_ticks_msec() / 1000.0

	checkpointSound = get_node(checkpointSoundPath) as AudioStreamPlayer
	countdownSound = get_node(countdownSoundPath) as AudioStreamPlayer
	finishSound = get_node(finishSoundPath) as AudioStreamPlayer

	get_node(bodyNode).material_override = material

	for w in wheels:
		w.dirt.emitting = false

	config = ConfigFile.new()
	var configPath = "config.ini"
	if config.load(configPath) == OK:
		springRate = float(config.get_value("setup", "spring_rate", 40))
		dampRate = float(config.get_value("setup", "damp_rate", 3))

		var volume = float(config.get_value("audio", "master_volume", 1))
		AudioServer.set_bus_volume_db(0, log(volume) * dbToVolume)

		drawParticles = float(config.get_value("graphics", "draw_particles", 1)) != 0
		drawLines = float(config.get_value("debug", "lines", 0)) != 0
		debugSplits = float(config.get_value("debug", "splits", 0)) != 0
	else:
		print("Couldn't load " + configPath)

func get_velocity_at_point(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_transform.origin)

static func repeat(t: float, length: float) -> float:
	return clamp(t - floor(t / length) * length, 0.0, length)

func sat(value: float) -> float:
	return clamp(value, 0, 1)

func get_sector_time(splits: Array, i: int) -> float:
	var lastCheckTime: float = 0 if i == 0 else splits[i - 1]
	return splits[i] - lastCheckTime

var isReplay: bool = false
var replaySample: int = 0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.scancode == KEY_F:
		isReplay = true
		replaySample = 0

func _physics_process(dt: float) -> void:
	if isReplay:
		transform = samples[replaySample].t
		replaySample += 1
		if replaySample == samples.size():
			replaySample = 0

	var time: float = OS.get_ticks_msec() / 1000.0

	if not stageEnded:
		stageTime = time - sceneStartTime - countdown

	var countdownTime: int = int(-stageTime) + 1

	timingText.clear()
	timingText.push_color(black)

	var stageTimeStr: String = "0.000" if stageTime < 0 else str(stageTime, "%.3f")
	var bestTimeStr: String = "--.---" if bestTime == 0 else str(bestTime, "%.3f")
	timingText.append_bbcode("Best: " + bestTimeStr + "\n")

	timingText.append_bbcode("Time: " + stageTimeStr + "\n")

	if checkpointPassed >= 0:
		var bestTimes = prevBestCheckpointTimes if stageEnded else bestCheckpointTimes

		for c in range(checkpointPassed + 1):
			var sectorTime: float = get_sector_time(checkpointTimes, c)
			var bestSectorTime: float = get_sector_time(bestTimes, c)

			if bestTime == 0 or sectorTime < bestSectorTime:
				timingText.push_color(darkGreen)
			else:
				timingText.push_color(red)

			timingText.append_bbcode("#")

		var diff: float = get_sector_time(checkpointTimes, checkpointPassed) - get_sector_time(bestTimes, checkpointPassed)
		timingText.append_bbcode("\nSplit: " + ("+" if diff > 0 else "") + str(diff, "%.3f"))

	if stageEnded:
		timingText.push_color(black)
		timingText.append_bbcode("\nFinished! Press R to restart")

	if stageTime < 0:
		if countdownTime != lastCountdownTime:
			countdownSound.play()
		lastCountdownTime = countdownTime
		countdownText.text = str(countdownTime)
	else:
		countdownText.text = ""

	var xInput: float = -1 if Input.is_key_pressed(KEY_A) else (1 if Input.is_key_pressed(KEY_D) else 0)
	var yInput: float = -1 if Input.is_key_pressed(KEY_S) else (1 if Input.is_key_pressed(KEY_W) else 0)

	var throttleInput: float = yInput

	if isReplay:
		yInput = samples[replaySample].throttle

	smoothSteer = lerp(smoothSteer, xInput, dt * 10)
	smoothThrottle = lerp(smoothThrottle, throttleInput, dt * 10)

	var steering: float = smoothSteer * 0.5
	var targetSpeed: float = maxSpeedKmh / 3.6
	var currentSpeed: float = linear_velocity.length()

	if currentSpeed > targetSpeed:
		targetSpeed = currentSpeed

	if currentSpeed < 0.1:
		targetSpeed = 0.0

	if smoothThrottle < 0:
		targetSpeed = 0.0

	var spaceState: PhysicsDirectSpaceState = get_world().direct_space_state
	
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var up: Vector3 = global_transform.basis.y
	
	var wheelsOnGround: int = 0
	
	var tractionPoint: Vector3 = Vector3.ZERO

	for w in wheels:
		var wheelPos: Vector3 = to_global(w.point)
		
		var origin: Vector3 = wheelPos + up * raycastHeightOffset
		var dest: Vector3 = origin - up * rayLength

		var result: Dictionary = spaceState.intersect_ray(origin, dest)

		var grounded: bool = result.size() > 0

		# suspension
		if grounded:
			w.wasGrounded = true
			
			var hitPoint: Vector3 = result["position"]
			var normal: Vector3 = result["normal"]

			var distFromTarget: float = (dest - hitPoint).length()
			
			var spring: float = springRate * distFromTarget
			
			#var traction: Vector3 = normal * (smoothThrottle * tractionForceMult)
			#add_central_force(traction)
			
			print(distFromTarget)
			
			var veloAtWheel: Vector3 = get_velocity_at_point(origin)
			var verticalVeloAtWheel: float = up.dot(veloAtWheel)
			
			var damp: float = -verticalVeloAtWheel * dampRate

			add_force(normal * (spring + damp), hitPoint - transform.origin)

			var sidewaysTraction: Vector3 = right * (smoothThrottle * sidewaysTractionMult * sidewaysTractionEase)
			sidewaysTraction = sidewaysTraction.linear_interpolate(Vector3.ZERO, dt * sidewaysTractionEase)
			#add_central_force(sidewaysTraction)

			#var v: Vector3 = (hitPoint - wheelPos).normalized()

			#line.add_point(hitPoint, black)
			#line.add_point(hitPoint + normal * 0.1, green)
			
			wheelsOnGround += 1
			
			tractionPoint += hitPoint

		else:
			if w.wasGrounded:
				w.wasGrounded = false
				if drawParticles:
					w.dirt.emitting = true
					
	

	if wheelsOnGround > 0:
		var wheelFactor: float = tractionPoint / wheelsOnGround
		
		var midPoint: Vector3 = tractionPoint / wheelsOnGround
		

	# WTF, on ubacio:
	#if !grounded and not wheels[0].wasGrounded and not wheels[1].wasGrounded:
		#add_torque(Vector3(0, smoothSteer * torqueMult, 0))

	var forwardVel: Vector3 = forward * linear_velocity.dot(forward)
	add_torque(Vector3(0, smoothSteer * torqueMult, 0))

	# Compute speed pitch
	if targetSpeed != 0:
		speedPitch = clamp(linear_velocity.length() / targetSpeed, 0, 1)
	else:
		speedPitch = 1
		
	engineAudio.pitch_scale = lerp(0.5, 1.5, speedPitch)

# TODO: rename to on_trigger_entered later
func BodyEntered(body: Node, checkpointIndex: int) -> void:
	if body.is_in_group("checkpoints"):
		#var checkpointIndex: int = body.get("checkpoint_index")

		if checkpointIndex > checkpointPassed:
			checkpointPassed = checkpointIndex
			checkpointTimes.append(OS.get_ticks_msec() / 1000.0)
			checkpointSound.play()

			if checkpointPassed >= CHECKPOINT_NUM:
				stageEnded = true
				finishSound.play()
				if bestTime == 0 or stageTime < bestTime:
					bestTime = stageTime
					bestCheckpointTimes = checkpointTimes.duplicate()

				if checkpointPassed == CHECKPOINT_NUM:
					countdownText.text = ""

				checkpointTimes = []
				prevBestCheckpointTimes = bestCheckpointTimes.duplicate()
