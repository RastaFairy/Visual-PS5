// SharpProspero - a C# SDK for on-device application modules.
// Copyright (C) 2026 SvenGDK

using SharpProspero.Graphics;
using System;
using System.Collections.Generic;

namespace SharpProspero.Ui;

/// <summary>
/// Places controls at pixel coordinates on a design canvas and scales the canvas uniformly to fit
/// its available area. Use this when a screen is authored with an absolute visual editor rather
/// than a flow layout.
/// </summary>
public sealed class AbsolutePanel(int designWidth, int designHeight) : UiElement
{
    private readonly List<Placement> _placements = [];

    /// <summary>The source canvas width in logical pixels.</summary>
    public int DesignWidth { get; } = designWidth > 0 ? designWidth : throw new ArgumentOutOfRangeException(nameof(designWidth));

    /// <summary>The source canvas height in logical pixels.</summary>
    public int DesignHeight { get; } = designHeight > 0 ? designHeight : throw new ArgumentOutOfRangeException(nameof(designHeight));

    /// <summary>Adds a control with its source-canvas position and size.</summary>
    public AbsolutePanel Add(UiElement child, int x, int y, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(child);
        if (width <= 0 || height <= 0)
            throw new ArgumentOutOfRangeException(nameof(width), "A placed control must have positive dimensions.");
        _placements.Add(new Placement(child, new UiRect(x, y, width, height)));
        return this;
    }

    /// <inheritdoc />
    public override int Measure(int width, UiTheme theme) => DesignHeight;

    /// <inheritdoc />
    internal override void Arrange(UiRect bounds, UiTheme theme)
    {
        Bounds = bounds;
        float scale = Math.Min((float)bounds.Width / DesignWidth, (float)bounds.Height / DesignHeight);
        int fittedWidth = (int)MathF.Round(DesignWidth * scale);
        int fittedHeight = (int)MathF.Round(DesignHeight * scale);
        int offsetX = bounds.X + (bounds.Width - fittedWidth) / 2;
        int offsetY = bounds.Y + (bounds.Height - fittedHeight) / 2;

        foreach (Placement placement in _placements)
        {
            UiRect source = placement.Bounds;
            int x = offsetX + (int)MathF.Round(source.X * scale);
            int y = offsetY + (int)MathF.Round(source.Y * scale);
            int right = offsetX + (int)MathF.Round(source.Right * scale);
            int bottom = offsetY + (int)MathF.Round(source.Bottom * scale);
            if (placement.Child is StyledElement styled)
                styled.LayoutScale = scale;
            placement.Child.Arrange(new UiRect(x, y, right - x, bottom - y), theme);
        }
    }

    /// <inheritdoc />
    internal override void CollectFocusables(List<UiElement> into)
    {
        foreach (Placement placement in _placements)
            if (Visible && placement.Child.Visible)
                placement.Child.CollectFocusables(into);
    }

    /// <inheritdoc />
    public override void Draw(Surface surface, UiTheme theme, UiElement? focused)
    {
        if (!Visible)
            return;
        foreach (Placement placement in _placements)
            if (placement.Child.Visible)
                placement.Child.Draw(surface, theme, focused);
    }

    private sealed record Placement(UiElement Child, UiRect Bounds);
}
