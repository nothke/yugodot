extends RigidBody3D

# Exports

@export var raycastHeightOffset: float = 0
const rayLength = 0.6

@export var springRate: float = 20
@export var dampRate = 2
@export var tractionEase: float = 2 # (float, EASE)
@export var maxSpeedKmh: float = 60
@export var sidewaysTractionEase: float = 1 # (float, EASE)
@export var maxTraction: float = 30
@export var tractionForceMult: float = 10
@export var sidewaysTractionMult: float = 1

@export var engineAudioPath: NodePath
@export var timingPath: NodePath
@export var countdownPath: NodePath

@export var checkpointSoundPath: NodePath
@export var countdownSoundPath: NodePath
@export var finishSoundPath: NodePath

# Car vars

var torqueMult: float = 10

var wheelBase: float = 1.05
var wheelTrack: float = 0.7

var wheelRoot: Node3D

var smoothThrottle: float
var smoothSteer: float # Used for graphics

var prevYInput: float

var  config: ConfigFile
var drawParticles = true
var drawPostProcessing = true
var drawShadows = true
#var drawLines = false
var debugSplits = false

class Wheel:
	var point: Vector3
	var graphical: Node3D
	var dirt: GPUParticles3D
	var wasGrounded: bool

var wheels = [] # TODO: Size is known, can we prealloc?

const wheelRadius: float = 0.3
const wheelGraphicalXOffset: float = -0.1

# Timing

var checkpointPassed: int = -1

var countdown: float = 4

var sceneStartTime: float

const CHECKPOINT_NUM: int = 13
var bestTime: float
# TODO: Init capacity to CHECKPOINT_NUM
var bestCheckpointTimes: PackedFloat32Array
var checkpointTimes: PackedFloat32Array
var prevBestCheckpointTimes: PackedFloat32Array

var stageEnded = false;

func race_started():
	return stageTime > 0

var stageTime: float

var lastCountdownTime: int

var timingText: RichTextLabel
var countdownText: RichTextLabel

# Replay

class ReplaySample:
	var t: Transform3D
	var time: float
	var throttle: float

var samples = [] # TODO: Init capacity..?

var isReplay: bool = false
var replaySampleIndex: int = 0

# Audio

var speedPitch: float

var checkpointSound: AudioStreamPlayer
var countdownSound: AudioStreamPlayer
var finishSound: AudioStreamPlayer
var engineAudio: AudioStreamPlayer3D

const dbToVolume = 8.685

func _ready():
	wheels.resize(4)
	for i in 4:
		wheels[i] = Wheel.new()
		
	wheels[0].point = Vector3(-wheelTrack, 0, wheelBase)
	wheels[1].point = Vector3(wheelTrack, 0, wheelBase)
	wheels[2].point = Vector3(-wheelTrack, 0, -wheelBase)
	wheels[3].point = Vector3(wheelTrack, 0, -wheelBase)


	wheels[0].graphical = get_node("car/RootNode/fl") as Node3D
	wheels[1].graphical = get_node("car/RootNode/fr") as Node3D
	wheels[2].graphical = get_node("car/RootNode/rl") as Node3D
	wheels[3].graphical = get_node("car/RootNode/rr") as Node3D
	wheelRoot = wheels[0].graphical.get_parent() as Node3D
	
	for w in wheels:
		var child: Node3D = w.graphical.get_child(0) as Node3D
		child.translate_object_local(Vector3.RIGHT * wheelGraphicalXOffset)

	wheels[0].dirt = get_node("dirt_fl") as GPUParticles3D
	wheels[1].dirt = get_node("dirt_fr") as GPUParticles3D
	wheels[2].dirt = get_node("dirt_rl") as GPUParticles3D
	wheels[3].dirt = get_node("dirt_rr") as GPUParticles3D

	engineAudio = get_node(engineAudioPath) as AudioStreamPlayer3D
	timingText = get_node(timingPath) as RichTextLabel
	countdownText = get_node(countdownPath) as RichTextLabel

	sceneStartTime = Time.get_ticks_msec() / 1000.0

	checkpointSound = get_node(checkpointSoundPath) as AudioStreamPlayer
	countdownSound = get_node(countdownSoundPath) as AudioStreamPlayer
	finishSound = get_node(finishSoundPath) as AudioStreamPlayer

	for w in wheels:
		w.dirt.emitting = false

	# line = get_node("wheel_debug") as LineDrawer3D

	config = ConfigFile.new()
	var configPath = "config.ini"
	if config.load(configPath) == OK:
		var cfgBool = func(segment, entry):
			return float(config.get_value(segment, entry, 1)) != 0
			
		springRate = float(config.get_value("setup", "spring_rate", 40))
		dampRate = float(config.get_value("setup", "damp_rate", 3))

		var volume = float(config.get_value("audio", "master_volume", 1))
		AudioServer.set_bus_volume_db(0, log(volume) * dbToVolume)

		drawParticles = cfgBool.call("graphics", "draw_particles")
		drawPostProcessing = cfgBool.call("graphics", "post_processing")
		drawShadows = cfgBool.call("graphics","post_processing")
		
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

func get_sector_time(splits: PackedFloat32Array, i: int) -> float:
	var lastCheckTime: float = 0.0 if i == 0 else splits[i - 1]
	return splits[i] - lastCheckTime



func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		isReplay = true
		replaySampleIndex = 0

func _physics_process(dt: float) -> void:
	if isReplay:
		var sample: ReplaySample = samples[replaySampleIndex] as ReplaySample
		transform = sample.t
		
		replaySampleIndex += 1
		if replaySampleIndex == samples.size():
			replaySampleIndex = 0

	# -- TIMING --

	var time: float = Time.get_ticks_msec() / 1000.0

	if not stageEnded:
		stageTime = time - sceneStartTime - countdown

	var countdownTime: int = int(-stageTime) + 1

	timingText.clear()
	timingText.push_color(Color.BLACK)

	var stageTimeStr: String = "0.000" if stageTime < 0 else "%.3f" % stageTime
	var bestTimeStr: String = "--.---" if bestTime == 0 else "%.3f" % bestTime
	timingText.append_text("Best: " + bestTimeStr + "\n")
	timingText.append_text("Time: " + stageTimeStr + "\n")

	if checkpointPassed >= 0:
		var bestTimes = prevBestCheckpointTimes if stageEnded else bestCheckpointTimes

		for c in range(checkpointPassed + 1):
			var sectorTime: float = get_sector_time(checkpointTimes, c)
			var bestSectorTime: float = get_sector_time(bestTimes, c)

			if bestTime == 0 or sectorTime < bestSectorTime:
				timingText.push_color(Color.GREEN)
			else:
				timingText.push_color(Color.RED)

			timingText.append_text("#")

		var diff: float = get_sector_time(checkpointTimes, checkpointPassed) - get_sector_time(bestTimes, checkpointPassed)
		timingText.append_text("\nSplit: " + ("+" if diff > 0 else "") + ("%.3f" % diff))

	if stageEnded:
		timingText.push_color(Color.BLACK)
		timingText.append_text("\nFinished! Press R to restart")

	if stageTime < 0:
		if countdownTime != lastCountdownTime:
			countdownSound.play()
		lastCountdownTime = countdownTime
		countdownText.text = str(countdownTime)
	else:
		countdownText.text = ""

	# -- INPUT --

	var xInput: float = -1 if Input.is_key_pressed(KEY_A) else (1 if Input.is_key_pressed(KEY_D) else 0)
	var yInput: float = -1 if Input.is_key_pressed(KEY_S) else (1 if Input.is_key_pressed(KEY_W) else 0)

	var throttleInput: float = yInput

	if isReplay:
		yInput = samples[replaySampleIndex].throttle

	smoothSteer = lerp(smoothSteer, xInput, dt * 10)

	smoothThrottle = lerp(smoothThrottle, throttleInput, dt * 10)

	if stageTime < 0:
		yInput = 0

	# -- PHYSICS --

	var speed: float = linear_velocity.length()

	var spaceState: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	# Car-dinal directions
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

		# Raycast

		var origin: Vector3 = wheelPos + up * raycastHeightOffset
		var dest: Vector3 = origin - up * rayLength
		
		var ray := PhysicsRayQueryParameters3D.create(origin, dest)
		var result: Dictionary = spaceState.intersect_ray(ray)

		var grounded: bool = result.size() > 0

		var graphicalWheelPoint: Vector3 = dest;

		# Suspension

		if grounded:
			var hitPoint: Vector3 = result["position"]
			var normal: Vector3 = result["normal"]
			
			var distFromTarget: float = (dest - hitPoint).length()

			var spring: float = springRate * distFromTarget

			var veloAtWheel: Vector3 = get_velocity_at_point(origin)
			var verticalVeloAtWheel: float = up.dot(veloAtWheel)

			var damp: float = -verticalVeloAtWheel * dampRate

			apply_force(normal * (spring + damp), hitPoint - transform.origin)

			wheelsOnGround += 1

			tractionPoint += hitPoint

			graphicalWheelPoint = hitPoint

		# Particles

		if drawParticles:
			var dirtSpeedFactor = -smoothSteer if i < 2 else 0.0
			w.dirt.rotation = Vector3(deg_to_rad(20), atan(-sidewaysSpeed * 0.1 + dirtSpeedFactor), 0)

			if grounded != w.wasGrounded || prevYInput != yInput:
				w.dirt.emitting = grounded and yInput > 0

		# Graphical wheel position and rotation

		var localWheelCenter = wheelRoot.to_local(graphicalWheelPoint + up * wheelRadius)
		w.graphical.position = localWheelCenter

		var wheelRot: Vector3 = Vector3.ZERO

		if i % 2 == 0:
			wheelRot = Vector3(0, deg_to_rad(180), 0)
		else:
			wheelRot = Vector3(0, deg_to_rad(0), 0)

		w.graphical.rotation = wheelRot

		if i < 2:
			w.graphical.rotate(Vector3.UP, -smoothSteer * deg_to_rad(30))
		
		w.wasGrounded = grounded

		i += 1

	# var gear: int = int(floor(forwardVelocity / 8))

	var gearPitch: float = repeat(forwardVelocity, 8.0) / 8.0
	speedPitch = lerp(speedPitch, speed * 0.1 * gearPitch, dt * 10)

	engineAudio.pitch_scale = clamp(lerp(speedPitch, smoothThrottle * 3, 0.5), 0.3, 10)

	if wheelsOnGround > 0:
		var wheelFactor: float = wheelsOnGround / 4.0
		var midPoint: Vector3 = tractionPoint / wheelsOnGround

		# Steering

		var steeringFactor = clamp(inverse_lerp(0, 5, speed), 0, 1)

		apply_torque(-transform.basis.y * xInput * torqueMult * steeringFactor)

		# Traction

		var maxSpeed = maxSpeedKmh / 3.6
		var tractionMult = 1.0 - ease(abs(forwardVelocity) / maxSpeed, tractionEase)
		var tractionForce = tractionMult * yInput * tractionForceMult * wheelFactor

		var sideAbs = abs(sidewaysSpeed)
		var sidewaysSign: int = int(sign(sidewaysSpeed))
		var earlyTraction: float = sat(sideAbs * 2.0) * sat(1 - sideAbs / 20.0) * 10.0
		var sidewaysTractionFac: float = (earlyTraction + ease(abs(sidewaysSpeed) / maxTraction, sidewaysTractionEase) * maxTraction) * sidewaysSign;

		var sidewaysTraction: Vector3 = -right * sidewaysTractionMult * sidewaysTractionFac
		var forwardTraction: Vector3 = forward * tractionForce

		apply_force(forwardTraction + sidewaysTraction, midPoint - transform.origin)

	prevYInput = yInput

	if not isReplay:
		var s = ReplaySample.new()
		s.t = transform
		s.time = stageTime
		s.throttle = throttleInput

		samples.append(s)

func on_entered_checkpoint(body: Node, checkpointIndex: int) -> void:
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
