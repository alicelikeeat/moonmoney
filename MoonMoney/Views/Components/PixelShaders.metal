#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Samples the layer on a coarse grid so it reads as chunky pixels.
[[ stitchable ]] half4 pixellate(float2 position, SwiftUI::Layer layer, float size) {
    float2 cell = (floor(position / size) + 0.5) * size;
    return layer.sample(cell);
}
