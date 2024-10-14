using Godot;
using System;

public class CarCamera : Camera
{
    [Export] public NodePath carPath;

    CarController car;

    public override void _Ready()
    {
        car = GetNode<CarController>(carPath);
        camPos = Translation;

        var config = new ConfigFile();
        const string CONFIG_PATH = "config.ini";
        if (config.Load(CONFIG_PATH) == Error.Ok)
        {
            raceSmoothing = float.Parse(config.GetValue("camera", "smoothing_rate", 7).ToString());
            height = float.Parse(config.GetValue("camera", "height", 3).ToString());
            distance = float.Parse(config.GetValue("camera", "distance", 6).ToString());
        }
        else GD.Print("Couldn't load " + CONFIG_PATH);
    }

    Vector3 camPos;
    Vector3 carPos;

    float startSmoothing = 1;
    float raceSmoothing = 7;
    float height = 3;
    float distance = 6;

    public override void _PhysicsProcess(float dt)
    {
        Vector3 carForward = car.Transform.basis.z;
        carPos = car.Translation;

        Vector3 rearTargetPoint = carPos - carForward * distance;
        rearTargetPoint.y = carPos.y + height;

        float smoothing = car.RaceStarted ? raceSmoothing : startSmoothing;

        camPos = camPos.LinearInterpolate(rearTargetPoint, dt * smoothing);

        /*
        float limit = 8;
        Vector3 diff = camPos - carPos;
        if ((diff).Length() > limit)
        {
            camPos = carPos + diff.Normalized() * limit;
        }*/
    }

    public override void _Process(float dt)
    {
        Translation = camPos;
        LookAt(carPos, Vector3.Up);
    }
}
