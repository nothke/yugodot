using Godot;
using System;

using Utility;
using System.Collections.Generic;

public class CarController : RigidBody
{
	LineDrawer3D line;

	[Export] public float raycastHeightOffset = 0;

	[Export] public float springRate = 20;
	[Export] public float dampRate = 2;
	[Export(PropertyHint.ExpEasing)] public float tractionEase = 2;
	[Export] public float maxSpeedKmh = 60;
	[Export(PropertyHint.ExpEasing)] public float sidewaysTractionEase = 1;
	[Export] public float maxTraction = 30;
	[Export] public float tractionForceMult = 10;
	[Export] public float sidewaysTractionMult = 1;

	[Export] public NodePath engineAudioPath;
	[Export] public NodePath timingPath;
	[Export] public NodePath countdownPath;

	[Export] public NodePath checkpointSoundPath;
	[Export] public NodePath countdownSoundPath;
	[Export] public NodePath finishSoundPath;

	[Export] public Material material;
	[Export] public NodePath bodyNode;

	AudioStreamPlayer checkpointSound;
	AudioStreamPlayer countdownSound;
	AudioStreamPlayer finishSound;

	AudioStreamPlayer3D engineAudio;

	public float torqueMult = 10;


	public float wheelBase = 1.05f;
	public float wheelTrack = 0.7f;

	Spatial wheelRoot;
	//MeshInstance[] graphicalWheels = new MeshInstance[4];
	//CPUParticles[] dirts = new CPUParticles[4];

	float smoothThrottle;

	int checkpointPassed = -1;

	RichTextLabel timingText;
	RichTextLabel countdownText;

	public float countdown = 4;

	public float sceneStartTime;

	const int CHECKPOINT_NUM = 13;
	static float bestTime;
	static float[] bestCheckpointTimes = new float[CHECKPOINT_NUM];
	float[] checkpointTimes = new float[CHECKPOINT_NUM];
	float[] prevBestCheckpointTimes = new float[CHECKPOINT_NUM];

	readonly Color red = new Color(1.0f, 0.0f, 0.0f);
	readonly Color blue = new Color(0f, 0.0f, 1.0f);
	readonly Color green = new Color(0.0f, 1.0f, 0.0f);
	readonly Color darkGreen = new Color(0.0f, 0.9f, 0.0f);
	readonly Color black = new Color(0, 0, 0);


	float prevYInput;

	ConfigFile config;
	bool drawParticles = true;
	bool drawLines = false;
	bool debugSplits = false;

	struct Wheel
	{
		public Vector3 point;
		public Spatial graphical;
		public Particles dirt;
		public bool wasGrounded;
	}

	Wheel[] wheels = new Wheel[4];


	bool stageEnded;

	public bool RaceStarted => stageTime > 0;

	float stageTime;

	float speedPitch;

	float smoothSteer;
	int lastCountdownTime = 0;

	struct ReplaySample
	{
		public Transform t;
		public float time;
		public float throttle;
	}

	List<ReplaySample> samples = new List<ReplaySample>(10000);

	public override void _Ready()
	{
		wheels[0].point = new Vector3(-wheelTrack, 0, wheelBase);
		wheels[1].point = new Vector3(wheelTrack, 0, wheelBase);
		wheels[2].point = new Vector3(-wheelTrack, 0, -wheelBase);
		wheels[3].point = new Vector3(wheelTrack, 0, -wheelBase);

		var lineGeometry = GetNode("wheel_debug");
		//GD.Print(lineGeometry);
		line = lineGeometry as LineDrawer3D;

		wheels[0].graphical = GetNode<MeshInstance>("car/RootNode/fl");
		wheels[1].graphical = GetNode<MeshInstance>("car/RootNode/fr");
		wheels[2].graphical = GetNode<MeshInstance>("car/RootNode/rl");
		wheels[3].graphical = GetNode<MeshInstance>("car/RootNode/rr");
		wheelRoot = wheels[0].graphical.GetParent<Spatial>();

		wheels[0].dirt = GetNode<Particles>("dirt_fl");
		wheels[1].dirt = GetNode<Particles>("dirt_fr");
		wheels[2].dirt = GetNode<Particles>("dirt_rl");
		wheels[3].dirt = GetNode<Particles>("dirt_rr");

		engineAudio = GetNode<AudioStreamPlayer3D>(engineAudioPath);

		timingText = GetNode<RichTextLabel>(timingPath);
		countdownText = GetNode<RichTextLabel>(countdownPath);

		sceneStartTime = OS.GetTicksMsec() / 1000.0f;

		checkpointSound = GetNode<AudioStreamPlayer>(checkpointSoundPath);
		countdownSound = GetNode<AudioStreamPlayer>(countdownSoundPath);
		finishSound = GetNode<AudioStreamPlayer>(finishSoundPath);

		GetNode<MeshInstance>(bodyNode).MaterialOverride = material;

		foreach (var w in wheels)
			w.dirt.Emitting = false;

		config = new ConfigFile();
		const string CONFIG_PATH = "config.ini";
		if (config.Load(CONFIG_PATH) == Error.Ok)
		{
			springRate = float.Parse(config.GetValue("setup", "spring_rate", 40).ToString());
			dampRate = float.Parse(config.GetValue("setup", "damp_rate", 3).ToString());

			float volume = float.Parse(config.GetValue("audio", "master_volume", 1).ToString());
			AudioServer.SetBusVolumeDb(0, Mathf.Log(volume) * 8.685f);

			drawParticles = float.Parse(config.GetValue("graphics", "draw_particles", 1).ToString()) != 0;
			drawLines = float.Parse(config.GetValue("debug", "lines", 0).ToString()) != 0;
			debugSplits = float.Parse(config.GetValue("debug", "splits", 0).ToString()) != 0;
		}
		else GD.Print("Couldn't load " + CONFIG_PATH);
	}

	Vector3 GetVelocityAtPoint(Vector3 point)
	{
		return LinearVelocity + AngularVelocity.Cross(point - GlobalTransform.origin);
	}


	public static float Repeat(float t, float length)
	{
		return Mathf.Clamp(t - Mathf.Floor(t / length) * length, 0.0f, length);
	}


	float sat(float value)
	{
		return Mathf.Clamp(value, 0, 1);
	}

	float GetSectorTime(float[] splits, int i)
	{
		float lastCheckTime = i == 0 ? 0 : splits[i - 1];
		return splits[i] - lastCheckTime;
	}

	bool isReplay;
	int replaySample = 0;

	public override void _Input(InputEvent e)
	{
		if (e is InputEventKey keyEvent)
		{
			if (keyEvent.Scancode == (uint)KeyList.F && keyEvent.Pressed)
			{
				isReplay = true;
				replaySample = 0;
			}
		}
	}

	public override void _PhysicsProcess(float dt)
	{

		if (isReplay)
		{
			Transform = samples[replaySample].t;
			replaySample++;

			if (replaySample == samples.Count)
				replaySample = 0;
		}


		float time = OS.GetTicksMsec() / 1000.0f;

		if (!stageEnded)
			stageTime = time - sceneStartTime - countdown;

		int countdownTime = (int)-stageTime + 1;

		//if (stageTime < 0)
		//stageTime = 0;

		timingText.Clear();
		timingText.PushColor(black);

		string stageTimeStr = stageTime < 0 ? "0.000" : stageTime.ToString("F3");

		string bestTimeStr = bestTime == 0 ? "--.---" : bestTime.ToString("F3");
		timingText.AppendBbcode("Best: " + bestTimeStr + "\n");

		if (!stageEnded)
			timingText.AppendBbcode(
				"Time: " + stageTimeStr + "\n");
		else
			timingText.AppendBbcode(
				"Time: " + stageTimeStr + "\n");

		if (checkpointPassed >= 0)
		{
			var bestTimes = stageEnded ? prevBestCheckpointTimes : bestCheckpointTimes;

			for (int c = 0; c <= checkpointPassed; c++)
			{
				float sectorTime = GetSectorTime(checkpointTimes, c);
				float bestSectorTime = GetSectorTime(bestTimes, c);

				if (bestTime == 0 || sectorTime < bestSectorTime)
					timingText.PushColor(darkGreen);
				else
					timingText.PushColor(red);

				timingText.AppendBbcode("#");
			}

			float diff = GetSectorTime(checkpointTimes, checkpointPassed) -
				GetSectorTime(bestTimes, checkpointPassed);

			timingText.AppendBbcode("\nSplit: " + (diff > 0 ? "+" : "") + diff.ToString("F3"));
		}

		if (stageEnded)
		{
			timingText.PushColor(black);
			timingText.AppendBbcode("\nFinished! Press R to restart");
		}

		if (stageTime < 0)
		{
			if (countdownTime != lastCountdownTime)
				countdownSound.Play();

			lastCountdownTime = countdownTime;

			countdownText.Text = countdownTime.ToString();
		}
		else countdownText.Text = "";

		float xInput =
			Input.IsKeyPressed((int)KeyList.A) ? -1 :
			(Input.IsKeyPressed((int)KeyList.D) ? 1 : 0);
		float yInput =
			Input.IsKeyPressed((int)KeyList.S) ? -1 :
			(Input.IsKeyPressed((int)KeyList.W) ? 1 : 0);

		float throttleInput = yInput;

		if (isReplay)
		{
			yInput = samples[replaySample].throttle;
		}

		smoothSteer = Mathf.Lerp(smoothSteer, xInput, dt * 10);

		smoothThrottle = Mathf.Lerp(smoothThrottle, yInput, dt * 3);

		if (stageTime < 0) // Disable input before stage start
			yInput = 0;

		// Drag shit:
		//AddCentralForce(-LinearVelocity * (1 - 0.05f));
		float speed = LinearVelocity.Length();
		//float forceFactor = 1 - (speed / 10.0f);
		//float forceFactor = Mathf.InverseLerp(10, 0, speed);

		var state = GetWorld().DirectSpaceState;
		var up = Transform.basis.y;
		var forward = Transform.basis.z;

		line.ClearLines();

		int wheelsOnGround = 0;

		float rayLength = 0.6f;

		//Color red = Color.ColorN(Colors.Red.ToString());
		//Color blue = Color.ColorN(Colors.Blue.ToString());



		//line.AddLine(Vector3.One * -10, Vector3.One * 10, red);

		Vector3 tractionPoint = new Vector3();



		Vector3 right = Transform.basis.x;
		float sidewaysSpeed = right.Dot(LinearVelocity);

		int i = 0;
		foreach (var w in wheels)
		{
			Vector3 wp = ToGlobal(w.point);

			var origin = wp + up * raycastHeightOffset;
			var dest = origin - up * rayLength;

			var dict = state.IntersectRay(origin, dest);

			Vector3 wheelP = dest;

			bool grounded = dict.Count > 0;

			if (grounded)
			{
				var obj = (Godot.Object)dict["collider"];
				Vector3 hit = (Vector3)dict["position"];
				Vector3 normal = (Vector3)dict["normal"];

				if (drawLines)
					line.AddLine(origin, hit, red);

				float distFromTarget = (dest - hit).Length();

				float spring = springRate * distFromTarget;

				Vector3 veloAtWheel = GetVelocityAtPoint(origin);
				float verticalVeloAtWheel = up.Dot(veloAtWheel);
				float damp = -verticalVeloAtWheel * dampRate;

				AddForce(normal * (spring + damp), hit - Transform.origin);

				wheelsOnGround++;

				wheelP = hit;
				tractionPoint += hit;

				//w.dirt.Direction = new Vector3(sidewaysSpeed * 0.1f, 0, -1);

			}
			else if (drawLines)
			{
				line.AddLine(origin, dest, blue);
			}

			if (drawParticles && (grounded != w.wasGrounded || prevYInput != yInput))
			{
				w.dirt.Emitting = grounded && yInput > 0;
			}

			float off = -0.1f;
			float rightoff = i % 2 == 0 ? -off : off;
			
			Vector3 localWheelCenter = wheelRoot.ToLocal(wheelP + up * 0.3f) + Vector3.Right * rightoff;
			w.graphical.Translation = localWheelCenter;
			//w.dirt.Translation = localWheelCenter;

			Vector3 wheelRot = Vector3.Zero;
			if (i % 2 == 0)
				wheelRot = new Vector3(0, Mathf.Deg2Rad(180), 0);
			else
				wheelRot = new Vector3(0, Mathf.Deg2Rad(0), 0);


			w.graphical.Rotation = wheelRot;

			if (i < 2)
				w.graphical.Rotate(Vector3.Up, -smoothSteer * Mathf.Deg2Rad(30));

			/*
			w.dirt.Rotation = wheelRot;

			if (i % 2 == 0)
			{
				w.dirt.Rotate(Vector3.Up, Mathf.Deg2Rad(180));
			}
			w.dirt.Rotate(Vector3.Right, Mathf.Deg2Rad(20));
			*/

			if (drawParticles)
			{
				float dirtSteerFactor = i < 2 ? -smoothSteer : 0;
				w.dirt.Rotation = new Vector3(Mathf.Deg2Rad(20), Mathf.Atan(-sidewaysSpeed * 0.1f + dirtSteerFactor), 0);
			}

			wheels[i].wasGrounded = grounded;

			i++;
		}

		Vector3 upPoint = Translation + up * 1.1f;

		if (drawLines)
		{
			line.AddLine(upPoint, upPoint + LinearVelocity, new Color(1, 1, 0));
			line.AddLine(upPoint, upPoint + right * sidewaysSpeed, red);
		}

		float forwardVelocity = forward.Dot(LinearVelocity);

		int gear = Mathf.FloorToInt(forwardVelocity / 8);

		float gearPitch = Repeat(forwardVelocity, 8) / 8.0f;
		speedPitch = Mathf.Lerp(speedPitch, speed * 0.1f * gearPitch, dt * 10);

		engineAudio.PitchScale = Mathf.Clamp(Mathf.Lerp(speedPitch, smoothThrottle * 3, 0.5f), 0.3f, 10);

		if (wheelsOnGround > 0)
		{
			float wheelFactor = wheelsOnGround / 4.0f;

			Vector3 midPoint = tractionPoint / wheelsOnGround;
			if (drawLines)
			{
				line.AddLine(midPoint, midPoint + up * 1, red);
				line.AddLine(midPoint, midPoint + Vector3.Right * 1, red);
				line.AddLine(midPoint, midPoint + Vector3.Forward * 1, red);
			}

			float steeringFactor = Mathf.Clamp(Mathf.InverseLerp(0, 5, speed), 0, 1);

			AddTorque(-Transform.basis.y * xInput * torqueMult * steeringFactor);

			float maxSpeed = maxSpeedKmh / 3.6f;
			float tractionMult = 1 - Mathf.Ease(Mathf.Abs(forwardVelocity) / maxSpeed, tractionEase);
			float tractionForce = tractionMult * yInput * tractionForceMult * wheelFactor;

			if (drawLines)
				line.AddLine(Vector3.Zero, Vector3.Up * tractionMult, red);

			float sideAbs = Mathf.Abs(sidewaysSpeed);
			int sidewaysSign = Mathf.Sign(sidewaysSpeed);
			float earlyTraction = sat(sideAbs * 2) * sat(1 - sideAbs / 20) * 10;
			float sidewaysTractionFac = (earlyTraction + Mathf.Ease(Mathf.Abs(sidewaysSpeed) / maxTraction, sidewaysTractionEase) * maxTraction) * sidewaysSign;

			Vector3 sidewaysTraction = -right * sidewaysTractionMult * sidewaysTractionFac;

			AddForce(
				forward * tractionForce + sidewaysTraction,
				midPoint - Transform.origin);


		}

		prevYInput = yInput;

		if (debugSplits)
		{
			string str = "";
			for (int c = 0; c < checkpointTimes.Length; c++)
			{
				str += checkpointTimes[c].ToString() + ", " + bestCheckpointTimes[c] + "\n";
			}
			countdownText.Text = str;
		}

		if (!isReplay)
		{
			samples.Add(new ReplaySample()
			{
				t = Transform,
				time = stageTime,
				throttle = throttleInput
			});
		}
	}

	public void BodyEntered(Node body, int i)
	{
		if (body == this)
		{
			GD.Print("Entered: " + body.Name + " id: " + i);
			if (checkpointPassed + 1 == i)
			{
				Check(i);
			}

			if (checkpointPassed == 12 && i == 0)
			{
				End();
			}
		}
	}

	void Check(int i)
	{
		checkpointPassed = i;
		checkpointSound.Play();

		checkpointTimes[i] = stageTime;
	}

	void End()
	{
		stageEnded = true;
		finishSound.Play();

		if (bestTime == 0 || stageTime < bestTime)
		{
			bestTime = stageTime;
			for (int i = 0; i < CHECKPOINT_NUM; i++)
			{
				prevBestCheckpointTimes[i] = bestCheckpointTimes[i];
				bestCheckpointTimes[i] = checkpointTimes[i];
			}
		}
	}
}
