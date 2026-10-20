#version 450
// ps5-homebrew-ui - Vulkan backdrop fragment shader: procedural backgrounds and post overlays.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kFragment in src/gfx/backdrop.cpp: change both together. Only the declarations
// differ: uniforms are push
// constants, and gl_FragCoord is read through frag_coord.

layout(push_constant) uniform Push
{
    vec2 resolution;
    float time;
    int mode;
    vec4 colors[4];
    vec4 params;
    float opacity;
    float flip; // 1: the target is stored top row first, -1: bottom row first
}
pc;

layout(location = 0) out vec4 frag_color;

// gl_FragCoord as OpenGL would report it (set first thing in main).
vec2 frag_coord;

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p)
{
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; ++i)
    {
        value += amplitude * noise(p);
        p = p * 2.03 + 17.1;
        amplitude *= 0.5;
    }
    return value;
}

float star_layer(vec2 p, float scale, float seed)
{
    vec2 g = p * scale;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id + seed);
    vec2 o = (vec2(hash(id + seed + 3.1), hash(id + seed + 7.7)) - 0.5) * 0.7;
    float twinkle = 0.6 + 0.4 * sin(pc.time * (1.0 + 3.0 * h) + h * 40.0);
    float size = 0.03 + 0.05 * fract(h * 17.0);
    return step(0.86, h) * smoothstep(size, 0.0, length(f - o)) * twinkle;
}

void main()
{
    // OpenGL counts gl_FragCoord rows up from the bottom of the target as it
    // is shown, Vulkan down from its first row in memory. A target stored
    // bottom row first (flip < 0) is already the same; the display is not.
    frag_coord = vec2(gl_FragCoord.x,
                      pc.flip < 0.0 ? gl_FragCoord.y : pc.resolution.y - gl_FragCoord.y);
    // uv: 0..1 with the origin at the top-left, like the virtual canvas.
    vec2 uv = vec2(frag_coord.x / pc.resolution.x, 1.0 - frag_coord.y / pc.resolution.y);
    float aspect = pc.resolution.x / pc.resolution.y;
    vec2 centred = (uv - 0.5) * vec2(aspect, 1.0);
    vec3 c0 = pc.colors[0].rgb;
    vec3 c1 = pc.colors[1].rgb;
    vec3 c2 = pc.colors[2].rgb;
    vec3 c3 = pc.colors[3].rgb;
    vec3 col = vec3(0.0);
    float alpha = 1.0;

    if (pc.mode == 1) // gradient
    {
        col = mix(c0, c1, smoothstep(0.0, 1.0, uv.y));
        vec2 d = (uv - pc.params.xy) * vec2(aspect, 1.0);
        col += c2 * pc.params.z * exp(-dot(d, d) * 3.0);
    }
    else if (pc.mode == 2) // aurora
    {
        vec2 p = uv * vec2(aspect, 1.0);
        float t = pc.time * 0.05;
        vec2 q = p * 1.4 + vec2(fbm(p * 1.2 + t), fbm(p * 1.2 - t + 7.3));
        float a = fbm(q + vec2(t * 0.7, -t * 0.4));
        float b = fbm(q * 1.7 - vec2(t * 0.3, t * 0.6) + 3.1);
        col = mix(c0, c1, smoothstep(0.1, 0.9, uv.y));
        col = mix(col, c2, smoothstep(0.42, 0.85, a) * 0.62);
        col = mix(col, c3, smoothstep(0.48, 0.9, b) * 0.45);
        col *= 1.0 - 0.35 * smoothstep(0.45, 1.1, length(centred));
    }
    else if (pc.mode == 3) // grid
    {
        float horizon = 0.56;
        if (uv.y < horizon)
        {
            float t = uv.y / horizon;
            col = mix(c0, c1, pow(t, 2.2));
            col += vec3(0.8) * step(0.9975, hash(floor(uv * vec2(640.0, 360.0)))) * (1.0 - t);
            vec2 s = vec2((uv.x - 0.5) * aspect, uv.y - (horizon - 0.13));
            float r = length(s);
            float sun = smoothstep(0.204, 0.2, r);
            float gap = clamp(s.y / 0.2, 0.0, 1.0);
            float cut = step(fract(s.y * 26.0 - pc.time * 0.12), gap * 0.62) * step(0.0, s.y);
            vec3 sun_colour = mix(c3, c2, clamp((s.y + 0.2) / 0.4, 0.0, 1.0));
            col = mix(col, sun_colour, sun * (1.0 - cut));
            col += c3 * 0.22 * exp(-r * r * 16.0);
        }
        else
        {
            float d = uv.y - horizon;
            float z = 0.08 / d;
            vec2 q = vec2((uv.x - 0.5) * aspect * z * 6.0, z * 2.2 + pc.time * 0.6);
            vec2 f = abs(fract(q - 0.5) - 0.5);
            vec2 aa = fwidth(q) * 1.5;
            vec2 l = 1.0 - smoothstep(vec2(0.018), vec2(0.018) + aa, f);
            float line = max(l.x, l.y) * clamp(d * 7.0, 0.0, 1.0);
            col = mix(c0 * 0.4, c2, line);
            col += c2 * 0.12 * (1.0 - clamp(d * 3.0, 0.0, 1.0));
        }
        col += c2 * 0.45 * exp(-abs(uv.y - horizon) * 46.0);
    }
    else if (pc.mode == 4) // stars
    {
        vec2 cam = pc.params.xy;
        col = mix(c0, c1, uv.y);
        float n = fbm(centred * 1.6 + cam * 0.15 + vec2(pc.time * 0.01, 0.0));
        float n2 = fbm(centred * 2.3 + cam * 0.1 + 5.2);
        col += c2 * smoothstep(0.45, 0.9, n) * 0.35;
        col += c3 * smoothstep(0.5, 0.95, n2) * 0.25;
        col += vec3(0.9) * star_layer(centred + cam * 0.05, 14.0, 1.0);
        col += vec3(0.6) * star_layer(centred + cam * 0.12, 26.0, 9.0);
        col += vec3(0.35) * star_layer(centred + cam * 0.25, 44.0, 23.0);
    }
    else if (pc.mode == 5) // waves
    {
        col = mix(c0, c1, uv.y);
        for (int i = 0; i < 5; ++i)
        {
            float fi = float(i);
            float y = 0.42 + fi * 0.1 +
                      0.05 * sin(uv.x * (2.0 + fi * 0.7) + pc.time * (0.25 + 0.07 * fi) + fi * 1.7) +
                      0.025 * sin(uv.x * (5.0 + fi) - pc.time * 0.2 + fi);
            vec3 ribbon = mix(c2, c3, fi / 4.0);
            col = mix(col, ribbon, smoothstep(y - 0.002, y + 0.002, uv.y) * 0.16);
            col += ribbon * 0.3 * exp(-abs(uv.y - y) * 220.0);
        }
    }
    else if (pc.mode == 6) // bokeh
    {
        col = mix(c0, c1, uv.y);
        vec2 p = vec2(uv.x * aspect, uv.y);
        for (int i = 0; i < 16; ++i)
        {
            float fi = float(i);
            float h1 = hash(vec2(fi, 1.3));
            float h2 = hash(vec2(fi, 7.9));
            float h3 = hash(vec2(fi, 13.1));
            vec2 c = vec2(h1 * aspect + 0.05 * sin(pc.time * 0.2 + fi),
                          fract(h2 - pc.time * (0.01 + 0.02 * h3)) * 1.3 - 0.15);
            float r = 0.05 + 0.13 * h3;
            col += mix(c2, c3, h1) * smoothstep(r, r * 0.75, length(p - c)) * (0.05 + 0.07 * h2);
        }
    }
    else if (pc.mode == 7) // phosphor
    {
        col = c0 + c1 * exp(-dot(centred, centred) * 1.6);
        col += c1 * 0.03 * hash(floor(uv * vec2(480.0, 270.0)) + floor(pc.time * 24.0));
    }
    else if (pc.mode == 8) // paper
    {
        col = mix(c0, c1, uv.y);
        vec2 d = (uv - vec2(0.15, 0.0)) * vec2(aspect, 1.0);
        col += c2 * 0.5 * exp(-dot(d, d) * 1.2);
        col += (hash(floor(uv * vec2(1920.0, 1080.0))) - 0.5) * 0.03;
    }
    else if (pc.mode == 9) // dots
    {
        col = mix(c0, c1, uv.y);
        vec2 p = vec2(uv.x * aspect, uv.y) * 36.0;
        vec2 f = fract(p) - 0.5;
        vec2 id = floor(p);
        float pulse = 0.5 + 0.5 * sin(length(id - vec2(18.0 * aspect, 18.0)) * 0.5 - pc.time * 1.2);
        float r = 0.06 + 0.08 * pulse;
        float fade = 1.0 - smoothstep(0.2, 0.9, length(centred));
        col += c2 * smoothstep(r, r - 0.04, length(f)) * (0.1 + 0.25 * pulse) *
               (0.35 + 0.65 * fade);
    }
    else if (pc.mode == 10) // vista
    {
        col = mix(c0, c1, smoothstep(0.0, 0.75, uv.y));
        vec2 s = vec2((uv.x - 0.72) * aspect, uv.y - 0.3);
        col += vec3(1.0, 0.9, 0.7) * 0.55 * exp(-dot(s, s) * 26.0);
        col = mix(col, vec3(1.0, 0.96, 0.84), smoothstep(0.062, 0.058, length(s)));
        for (int i = 0; i < 4; ++i)
        {
            float fi = float(i);
            float depth = fi / 3.0;
            float x = uv.x * (1.2 + fi * 0.6) + pc.time * pc.params.x * (0.02 + 0.05 * fi * fi) +
                      fi * 13.7;
            float h = 0.5 + 0.11 * fi + (fbm(vec2(x * 1.6, fi * 3.1)) - 0.5) * (0.28 - 0.03 * fi);
            vec3 ridge = mix(mix(c2, c3, depth), c1, (1.0 - depth) * 0.55);
            col = mix(col, ridge, smoothstep(h - 0.002, h + 0.002, uv.y));
        }
    }
    else if (pc.mode == 20) // scanlines (post)
    {
        float line = 0.5 + 0.5 * cos(uv.y * 1080.0 * 3.14159265 / 1.5);
        alpha = pc.params.x * line;
        alpha = max(alpha, pc.params.y * smoothstep(0.45, 1.05, length(centred)));
    }
    else if (pc.mode == 21) // vignette (post)
    {
        col = c0;
        alpha = pc.params.x * smoothstep(0.45, 1.1, length(centred));
    }

    // A little noise hides the banding of slow gradients on TVs.
    if (pc.mode < 20)
        col += (hash(frag_coord.xy + fract(pc.time) * 61.0) - 0.5) / 255.0;
    frag_color = vec4(col, alpha * pc.opacity);
}
