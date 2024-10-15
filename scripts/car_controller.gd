extends Node

export var raycastHeightOffset: float = 0

export var springRate: float = 20
export var dampRate = 2
#[Export(PropertyHint.ExpEasing)] public float tractionEase = 2;
export var maxSpeedKmh: float = 60
#[Export(PropertyHint.ExpEasing)] public float sidewaysTractionEase = 1;
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

class ReplaySample:
	var t: Transform
	var time: float
	var throttle: float

var samples = [] # TODO: Init capacity..?

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
