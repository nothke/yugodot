using Godot;
using System;

public class ParticlesTest : Particles
{
    public override void _Process(float delta)
    {
        float time = OS.GetTicksMsec() / 1000.0f;

        Emitting = Mathf.Sin(time * 20) > 0;
    }
}
