using Godot;
using System.Collections.Generic;

namespace Utility
{
    class LineDrawer3D : ImmediateGeometry
    {
        struct Line
        {
            public Vector3 p1;
            public Vector3 p2;
            public Color color;
        }

        List<Line> lines = new List<Line>();

        public void AddLine(Vector3 p1, Vector3 p2, Color color)
        {
            lines.Add(new Line() { p1 = p1, p2 = p2, color = color });
        }

        public void ClearLines()
        {
            lines.Clear();
        }

        public override void _Process(float delta)
        {
            base._Process(delta);

            Clear();

            Begin(Mesh.PrimitiveType.Lines);

            for (int i = 0; i < lines.Count; ++i)
            {
                SetColor(lines[i].color);
                AddVertex(ToLocal(lines[i].p1));
                AddVertex(ToLocal(lines[i].p2));
            }

            End();
        }
    }
}