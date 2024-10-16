extends RigidBody

export var raycastHeightOffset: float = 0
const rayLength = 0.6

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

var torqueMult: float = 10

var wheelBase: float = 1.05
var wheelTrack: float = 0.7

var wheelRoot: Spatial

var smoothThrottle: float
var smoothSteer: float # Used for graphics

var prevYInput: float

var  config: ConfigFile
var drawParticles = true
#var drawLines = false
var debugSplits = false

class Wheel:
	var point: Vector3
	var graphical: Spatial
	var dirt: Particles
	var wasGrounded: bool

var wheels = [] # TODO: Size is known, can we prealloc?

# Timing

var checkpointPassed: int = -1

var countdown: float = 4

var sceneStartTime: float

const CHECKPOINT_NUM: int = 13
var bestTime: float
# TODO: Init capacity to CHECKPOINT_NUM
var bestCheckpointTimes: PoolRealArray
var checkpointTimes: PoolRealArray
var prevBestCheckpointTimes: PoolRealArray

var stageEnded = false;

func race_started():
	return stageTime > 0

var stageTime: float

var lastCountdownTime: int

var timingText: RichTextLabel
var countdownText: RichTextLabel

# Replay

class ReplaySample:
	var t: Transform
	var time: float
	var throttle: float

var samples = [] # TODO: Init capacity..?

var isReplay: bool = false
var replaySample: int = 0

# Audio

var speedPitch: float

var checkpointSound: AudioStreamPlayer
var countdownSound: AudioStreamPlayer
var finishSound: AudioStreamPlayer
var engineAudio: AudioStreamPlayer3D

const dbToVolume = 8.685

# Debugging

const red = Color(1.0, 0.0, 0.0)
const blue = Color(0, 0.0, 1.0)
const green = Color(0.0, 1.0, 0.0)
const darkGreen = Color(0.0, 0.9, 0.0)
const black = Color(0, 0, 0)

func _ready():
	wheels.resize(4)
	for i in 4:
		wheels[i] = Wheel.new()
	
	wheels[0].point = Vector3(-wheelTrack, 0, wheelBase)
	wheels[1].point = Vector3(wheelTrack, 0, wheelBase)
	wheels[2].point = Vector3(-wheelTrack, 0, -wheelBase)
	wheels[3].point = Vector3(wheelTrack, 0, -wheelBase)


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

	# line = get_node("wheel_debug") as LineDrawer3D

	config = ConfigFile.new()
	var configPath = "config.ini"
	if config.load(configPath) == OK:
		springRate = float(config.get_value("setup", "spring_rate", 40))
		dampRate = float(config.get_value("setup", "damp_rate", 3))

		var volume = float(config.get_value("audio", "master_volume", 1))
		AudioServer.set_bus_volume_db(0, log(volume) * dbToVolume)

		drawParticles = float(config.get_value("graphics", "draw_particles", 1)) != 0
		#drawLines = float(config.get_value("debug", "lines", 0)) != 0
		debugSplits = float(config.get_value("debug", "splits", 0)) != 0
	else:
		print("Couldn't load " + configPath)
		
	checkpointPassed = -1
	
	checkpointTimes.resize(CHECKPOINT_NUM)
	bestCheckpointTimes.resize(CHECKPOINT_NUM)
	prevBestCheckpointTimes.resize(CHECKPOINT_NUM)
	
	for i in CHECKPOINT_NUM:
		checkpointTimes[i] = 0
		bestCheckpointTimes[i] = 0
		prevBestCheckpointTimes[i] = 0

func get_velocity_at_point(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_transform.origin)

static func repeat(t: float, length: float) -> float:
	return clamp(t - floor(t / length) * length, 0.0, length)

static func sat(value: float) -> float:
	return clamp(value, 0, 1)

func get_sector_time(splits: PoolRealArray, i: int) -> float:
	var lastCheckTime: float = 0.0 if i == 0 else splits[i - 1]
	return splits[i] - lastCheckTime



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

	var stageTimeStr: String = "0.000" if stageTime < 0 else "%.3f" % stageTime
	var bestTimeStr: String = "--.---" if bestTime == 0 else "%.3f" % bestTime
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
		timingText.append_bbcode("\nSplit: " + ("+" if diff > 0 else "") + ("%.3f" % diff))

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
		
	# INPUT

	var xInput: float = -1 if Input.is_key_pressed(KEY_A) else (1 if Input.is_key_pressed(KEY_D) else 0)
	var yInput: float = -1 if Input.is_key_pressed(KEY_S) else (1 if Input.is_key_pressed(KEY_W) else 0)

	var throttleInput: float = yInput

	if isReplay:
		yInput = samples[replaySample].throttle

	smoothSteer = lerp(smoothSteer, xInput, dt * 10)
	
	smoothThrottle = lerp(smoothThrottle, throttleInput, dt * 10)
	
	if stageTime < 0:
		yInput = 0
		
	var speed: float = linear_velocity.length()
	
	var spaceState: PhysicsDirectSpaceState = get_world().direct_space_state
	
	var up: Vector3 = global_transform.basis.y
	var forward: Vector3 = global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	
	var forwardVelocity: float = forward.dot(linear_velocity)
	var sidewaysSpeed: float = right.dot(linear_velocity)
	
	var wheelsOnGround: int = 0
	
	var tractionPoint: Vector3 = Vector3.ZERO
	
	var i: int = 0
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

		if drawParticles and (grounded != w.wasGrounded || prevYInput != yInput):
			w.dirt.emitting = true
		
		var localWheelCenter = wheelRoot.to_local(dest + up * 0.3)
		w.graphical.translation = localWheelCenter
		
		var wheelRot: Vector3 = Vector3.ZERO
		
		if i % 2 == 0:
			wheelRot = Vector3(0, deg2rad(180), 0)
		else:
			wheelRot = Vector3(0, deg2rad(0), 0)
			
		w.graphical.rotation = wheelRot
		
		if i < 2:
			w.graphical.rotate(Vector3.UP, -smoothSteer * deg2rad(30))
			
		if drawParticles:
			var dirtSpeedFactor = -smoothSteer if i < 2 else 0.0
			w.dirt.rotation = Vector3(deg2rad(20), atan(-sidewaysSpeed * 0.1 + dirtSpeedFactor), 0)
		
		w.wasGrounded = grounded
		
		i += 1
		
	# var gear: int = int(floor(forwardVelocity / 8))
	
	var gearPitch: float = repeat(forwardVelocity, 8.0) / 8.0
	speedPitch = lerp(speedPitch, speed * 0.1 * gearPitch, dt * 10)
	
	engineAudio.pitch_scale = clamp(lerp(speedPitch, smoothThrottle * 3, 0.5), 0.3, 10)

	# TRACTION
	if wheelsOnGround > 0:
		var wheelFactor: float = wheelsOnGround / 4.0
		
		var midPoint: Vector3 = tractionPoint / wheelsOnGround
		
		var steeringFactor = clamp(inverse_lerp(0, 5, speed), 0, 1)
		
		add_torque(-transform.basis.y * xInput * torqueMult * steeringFactor)
		
		var maxSpeed = maxSpeedKmh / 3.6
		var tractionMult = 1.0 - ease(abs(forwardVelocity) / maxSpeed, tractionEase)
		var tractionForce = tractionMult * yInput * tractionForceMult * wheelFactor

		var sideAbs = abs(sidewaysSpeed)
		var sidewaysSign: int = int(sign(sidewaysSpeed))
		var earlyTraction: float = sat(sideAbs * 2.0) * sat(1 - sideAbs / 20.0) * 10.0
		var sidewaysTractionFac: float = (earlyTraction + ease(abs(sidewaysSpeed) / maxTraction, sidewaysTractionEase) * maxTraction) * sidewaysSign;
		
		var sidewaysTraction: Vector3 = -right * sidewaysTractionMult * sidewaysTractionFac
		
		add_force(forward * tractionForce + sidewaysTraction, midPoint - transform.origin)
		
	prevYInput = yInput
	
	if not isReplay:
		var s = ReplaySample.new()
		s.t = transform
		s.time = stageTime
		s.throttle = throttleInput
		
		samples.append(replaySample)
		
# TODO: rename to on_trigger_entered later
func BodyEntered(body: Node, checkpointIndex: int) -> void:
	if body == self:
		print("Entered " + str(checkpointIndex))
		
		if checkpointPassed + 1 == checkpointIndex:
			print("Valid checkpoint!")
			
			checkpointPassed = checkpointIndex;
			checkpointSound.play();

			checkpointTimes[checkpointIndex] = stageTime;
			
		if checkpointPassed == 12 && checkpointIndex == 0:
			stageEnded = true;
			finishSound.play();

			if bestTime == 0 or stageTime < bestTime:
				bestTime = stageTime;
				for i in CHECKPOINT_NUM:
					prevBestCheckpointTimes[i] = bestCheckpointTimes[i];
					bestCheckpointTimes[i] = checkpointTimes[i];
		
