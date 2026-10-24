// SharpProspero - a C# SDK for on-device application modules.
// Copyright (C) 2026 SvenGDK

using SharpProspero.Graphics;
using System;
using System.Collections.Generic;

namespace SharpProspero.Ui;

/// <summary>
/// Applies per-control foreground and panel colors while preserving the wrapped control's drawing,
/// focus, layout, and input behavior.
/// </summary>
public sealed class StyledElement(UiElement child, Color? background = null, Color? foreground = null, int textScale = 2) : UiElement
{
    /// <summary>The wrapped native control.</summary>
    public UiElement Child { get; } = child ?? throw new ArgumentNullException(nameof(child));

    /// <summary>The control fill, or null to keep the theme's panel colors.</summary>
    public Color? Background { get; set; } = background;

    /// <summary>The control text color, or null to keep the theme's text colors.</summary>
    public Color? Foreground { get; set; } = foreground;

    /// <summary>The bitmap font scale used by controls that inherit their size from the theme.</summary>
    public int TextScale { get; set; } = Math.Clamp(textScale, 1, 12);

    /// <summary>Uniform scale supplied by the containing design canvas.</summary>
    internal float LayoutScale { get; set; } = 1f;

    /// <inheritdoc />
    public override bool IsFocusable => Visible && Child.Visible && Child.IsFocusable;

    /// <inheritdoc />
    public override int Measure(int width, UiTheme theme) => Child.Measure(width, theme);

    /// <inheritdoc />
    internal override void Arrange(UiRect bounds, UiTheme theme)
    {
        Bounds = bounds;
        Child.Arrange(bounds, theme);
    }

    /// <inheritdoc />
    internal override void CollectFocusables(List<UiElement> into)
    {
        if (Visible && Child.Visible)
            Child.CollectFocusables(into);
    }

    /// <inheritdoc />
    public override bool HandleInput(UiInput input, UiTheme theme) => Child.HandleInput(input, theme);

    /// <inheritdoc />
    internal override bool HandleCancel() => Child.HandleCancel();

    /// <inheritdoc />
    public override void Draw(Surface surface, UiTheme theme, UiElement? focused)
    {
        if (!Visible || !Child.Visible)
            return;

        if (Background is Color fill)
            surface.FillRect(Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height, fill);

        UiTheme localTheme = new()
        {
            Background = theme.Background,
            Panel = Background ?? theme.Panel,
            PanelFocused = Background ?? theme.PanelFocused,
            Accent = theme.Accent,
            Text = Foreground ?? theme.Text,
            TextMuted = Foreground ?? theme.TextMuted,
            Border = theme.Border,
            TextScale = Math.Clamp((int)MathF.Round(TextScale * LayoutScale), 1, 12),
            Padding = theme.Padding,
            Spacing = theme.Spacing,
        };
        // A caller-supplied scalable font is kept; the theme's lazy bitmap font must be recreated
        // at this control's text scale instead of reusing the global cached instance.
        if (theme.Font is not BitmapTextFont)
            localTheme.Font = theme.Font;
        Child.Draw(surface, localTheme, focused);
    }
}
