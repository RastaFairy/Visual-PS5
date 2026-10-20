// ps5-homebrew-ui - Frame composition: backdrops, draw lists and frosted glass.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gfx/renderer.hpp"

namespace hui::gfx
{

void Renderer::begin()
{
    layers_.clear();
}

void Renderer::backdrop(const BackdropSpec &spec, float opacity)
{
    if (spec.mode == BackdropMode::none || opacity <= 0.0f)
        return;
    Layer layer;
    layer.kind = Kind::backdrop;
    layer.spec = spec;
    layer.opacity = opacity;
    layers_.push_back(layer);
}

void Renderer::draw(const DrawList &list)
{
    if (list.empty())
        return;
    Layer layer;
    layer.kind = Kind::list;
    layer.list = &list;
    layers_.push_back(layer);
}

void Renderer::glass()
{
    Layer layer;
    layer.kind = Kind::glass;
    layers_.push_back(layer);
}

} // namespace hui::gfx
