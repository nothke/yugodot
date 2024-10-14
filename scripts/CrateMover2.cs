using Godot;
using System;

public class CrateMover2 : Spatial
{
    public override void _Ready()
    {

    }

    public override void _Process(float delta)
    {
        if (Input.IsKeyPressed((int)KeyList.A))
        {
            Transform = Transform.Translated(Vector3.Forward * delta);
        }
    }
}
