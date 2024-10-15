using Godot;
using System;

public class Game : Node
{
    [Export] NodePath hoodCameraPath;
    [Export] NodePath wingmanCameraPath;
    [Export] NodePath tracksideCameraPath;

    Camera hoodCamera;
    Camera wingmanCamera;
    Camera tracksideCamera;

    bool hoodCameraIsActive;

    public override void _Ready()
    {
        wingmanCamera = GetNode<Camera>(wingmanCameraPath);
        hoodCamera = GetNode<Camera>(hoodCameraPath);
        tracksideCamera = GetNode<Camera>(tracksideCameraPath);

        wingmanCamera.MakeCurrent();
    }

    bool hasRestarted;

    public override void _Input(InputEvent e)
    {
        if (e is InputEventKey keyEvent)
        {
            if (keyEvent.Scancode == (uint)KeyList.R && keyEvent.Pressed)
            {
                GetTree().ReloadCurrentScene();
                hasRestarted = true;
            }

            if (keyEvent.Scancode == (uint)KeyList.C && keyEvent.Pressed)
            {
                hoodCameraIsActive = !hoodCameraIsActive;

                if (hoodCameraIsActive)
                    hoodCamera.MakeCurrent();
                else
                    wingmanCamera.MakeCurrent();
            }

            if (keyEvent.Scancode == (uint)KeyList.V)
            {
                tracksideCamera.MakeCurrent();
            }
        }
    }

    public override void _Process(float delta)
    {
    }
}
