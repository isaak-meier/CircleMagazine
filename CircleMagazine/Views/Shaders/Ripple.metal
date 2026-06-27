//
//  Ripple.metal
//  CircleMagazine
//
//  Stitchable water-ripple distortion for SwiftUI's `layerEffect`. A wave
//  radiates from `origin`: each pixel is offset along the radial direction by a
//  decaying sine, delayed by its distance / speed so the front travels outward.
//  (Apple's "ripple" sample, adapted.)
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 Ripple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float time,
    float amplitude,
    float frequency,
    float decay,
    float speed
) {
    float distance = length(position - origin);
    float delay = distance / speed;

    time = max(0.0, time - delay);

    float rippleAmount = amplitude * sin(frequency * time) * exp(-decay * time);
    float2 n = normalize(position - origin);

    float2 newPosition = position + rippleAmount * n;
    half4 color = layer.sample(newPosition);

    // Subtle highlight on the crest so the wave reads as refraction.
    color.rgb += 0.3 * (rippleAmount / amplitude) * color.a;

    return color;
}
