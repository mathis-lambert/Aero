// The onboarding's wind (docs/ONBOARDING.md › Presentation): the mistral field drawn as dots on a fixed grid,
// like the pixels of a screen, with a shape written into it. Nothing is drawn over the grid: a new shape arrives
// from upwind behind a frayed front while the old one is carried downwind, and ripples cross it from a point.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

namespace {
    constant float windScale = 320.0;      // wavelength of the field, in points
    constant float2 wind = float2(0.9135455, 0.4067366); // 24°, rising to the right
    constant float contrast = 1.3;
    constant float seed = 3.0;
    constant float parting = 34.0;         // how far the air parts around the pointer, in points
    constant float partingRadius = 120.0;
    constant float carry = 120.0;          // how far a leaving or arriving shape travels, in points
    constant float warpDistance = 60.0;
    constant float frontLag = 0.14;        // the new shape follows the old one's departure
    constant float span = 0.5;             // share of the morph each cell takes to change
    constant float landingSwell = 0.28;    // dots grow a little as the shape lands
    constant float rippleWidth = 34.0;
    constant float ripplePush = 22.0;

    float hash(float2 p) {
        float3 q = fract(float3(p.xyx) * 0.1031);
        q += dot(q, q.yzx + 33.33);
        return fract((q.x + q.y) * q.z);
    }

    float noise(float2 x) {
        float2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }

    float fbm(float2 p) {
        float s = 0.0, a = 0.5;
        for (int o = 0; o < 4; o++) { s += a * noise(p); p = p * 2.03 + float2(17.1, 3.7); a *= 0.5; }
        return s;
    }

    float mask(texture2d<half> shape, float2 point, float2 size) {
        constexpr sampler linear(address::clamp_to_edge, filter::linear);
        return float(shape.sample(linear, point / size).r);
    }
}

[[ stitchable ]] half4 onboardingWind(float2 position, half4 current, float2 size, float pitch, float pixel, float time,
                                      float2 shift, float2 pointer, float near, float fade, float back,
                                      float k, half4 ink, half4 paper,
                                      texture2d<half> oldShape, texture2d<half> newShape,
                                      device const float *ripples, int rippleCount) {
    float2 cell = floor(position / pitch);
    float2 c = (cell + 0.5) * pitch;

    // The field at the cell's center: the air parts around the pointer and ripples push it outward.
    float2 d = c - pointer;
    float nearby = exp(-dot(d, d) / (partingRadius * partingRadius)) * near;
    float2 q = c - shift - normalize(d + 1e-4) * nearby * parting;
    float ring = 0.0;
    for (int i = 0; i + 3 < rippleCount; i += 4) {
        float2 e = c - float2(ripples[i], ripples[i + 1]);
        float distance = length(e);
        float r = exp(-pow((distance - ripples[i + 2]) / rippleWidth, 2.0)) * ripples[i + 3];
        ring += r;
        q -= e / (distance + 1e-3) * r * ripplePush;
    }
    float u = dot(q, wind) / windScale + seed * 13.1, v = dot(q, float2(-wind.y, wind.x)) / windScale + seed * 7.7;
    float px = u * 0.45, py = v * 1.6;
    float qx = fbm(float2(px + time * 0.15, py)), qy = fbm(float2(px + 5.2, py + 1.3 - time * 0.1));
    float f = fbm(float2(px + 1.9 * qx + time * 0.08, py + 1.9 * qy));
    float dark = 1.0 - clamp((f - 0.5) * contrast + 0.5, 0.0, 1.0);

    // The morph: a front along the wind, frayed so it never reads as a straight wipe.
    float front = clamp(dot(c, wind) / (size.x * wind.x + size.y * wind.y), 0.0, 1.0);
    float delay = (front * 0.65 + fbm(c / 110.0 + 3.1) * 0.35) * (1.0 - span - frontLag);
    float leaving = clamp((k - delay) / span, 0.0, 1.0), arriving = clamp((k - delay - frontLag) / span, 0.0, 1.0);
    float eo = leaving * leaving, en = 1.0 - pow(1.0 - arriving, 3.0);
    float2 warp = float2(fbm(c / 170.0 + time * 0.4), fbm(c / 170.0 + 9.7 - time * 0.4)) - 0.5;
    float mo = mask(oldShape, c - wind * eo * carry - warp * eo * warpDistance, size) * (1.0 - smoothstep(0.25, 1.0, leaving));
    float mn = mask(newShape, c + wind * (1.0 - en) * carry - warp * (1.0 - en) * warpDistance, size) * smoothstep(0.0, 0.55, arriving);
    float m = max(mo, mn);

    dark = mix(dark * back, 0.5 + 0.5 * dark, m);
    dark *= 1.0 - fade * (1.0 - m * 0.8);   // a quiet field keeps its shapes
    dark += sin(M_PI_F * arriving) * mn * landingSwell;
    dark = clamp(dark + ring * 0.55, 0.0, 1.0) * (1.0 - nearby * 0.6);

    // The dot of this cell: a disc whose size follows the darkness.
    float2 local = position / pitch - cell - 0.5;
    float aa = 0.75 * pixel / pitch, r = sqrt(dark) * 0.56;
    float cover = (1.0 - smoothstep(r - aa, r + aa, length(local))) * step(0.05, r);
    return mix(paper, ink, half(cover));
}
