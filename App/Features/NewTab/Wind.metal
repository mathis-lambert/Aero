// The New Tab page's wind: the mistral field of Scripts/generate-app-icon.swift drawn as dots whose
// radius grows with darkness, in a crescent near the bottom edge, with the gust and its light.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

namespace {
    // The dots.
    constant float pitch = 5.0;            // grid pitch, in points
    constant float dotScale = 0.46;        // largest dot radius, as a share of the pitch: dots never touch
    constant float faintest = 0.08;        // dots shrink to nothing at this darkness, so the page never looks dusty

    // The crescent.
    constant float crest = 0.7;            // its top, as a share of the height
    constant float breath = 5.0;           // how far the crest rises and falls, in points
    constant float sway = 26.0;            // how far its line wanders, in points
    constant float2 reach = float2(0.7, 0.9); // the ellipse's radii, as shares of the width and height
    constant float band = 34.0;            // half-width at the crest; it tapers toward the ends
    constant float spray = 60.0;           // how far dots scatter above it
    constant float haze = 80.0;            // how far the glow below it reaches
    constant float hazeStrength = 0.2;
    constant float sprayStrength = 0.22;

    // The wind.
    constant float windScale = 300.0;      // wavelength of the field
    constant float drift = 0.09;           // field widths per second along the wind
    constant float2 windDirection = float2(0.9135455, 0.4067366); // 24°, rising to the right

    // The gust. It travels fast, but what it does to each point unfolds in its own time.
    constant float ragged = 70.0;          // how uneven its front is, in points
    constant float blast = 8.0;           // how far it pushes the texture, in points
    constant float settleTime = 0.4;      // how long the push takes to die out, in seconds
    constant float swingTime = 0.7;       // period of the push's damped swing, in seconds
    constant float growTime = 0.75;         // how long a dot takes to grow in, in seconds
    constant float growScatter = 0.08;     // how much each dot's growth is delayed at most, in seconds
    constant float swell = 0.25;            // how much larger dots are right as the gust passes
    constant float swellTime = 0.22;       // how long that swelling lasts, in seconds
    constant float overshoot = 0.8;        // the growth's back-out easing, for a slight pop past full size

    // The light the gust carries to the control bar.
    constant float lightStrength = 0.07;
    constant float lightFade = 0.5;       // how long it lingers on the bar after arriving, in seconds

    float hash(float2 p) {
        uint2 q = uint2(int2(p));
        uint h = q.x * 374761393u + q.y * 668265263u;
        h = (h ^ (h >> 13)) * 1274126177u;
        return float(h ^ (h >> 16)) / 4294967296.0;
    }

    /// Value noise with quintic easing, smooth enough that no crease shows along the lattice.
    float noise(float2 p) {
        float2 i = floor(p), f = p - i, u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
        return a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
    }

    float fbm(float2 p) {
        float sum = 0.0, amplitude = 0.5;
        for (int octave = 0; octave < 4; octave++) {
            sum += amplitude * noise(p);
            p = p * 2.03 + float2(17.1, 3.7);
            amplitude *= 0.5;
        }
        return sum;
    }

    /// Warped noise stretched along the wind; the warp moves slower than the flow, so the gusts
    /// change shape as they travel instead of sliding rigidly.
    float wind(float2 point, float time) {
        float u = dot(point, windDirection) / windScale + 39.3 - time * drift;
        float v = dot(point, float2(-windDirection.y, windDirection.x)) / windScale + 23.1;
        float2 q = float2(u * 0.45, v * 1.6);
        float2 warp = float2(fbm(q + float2(0.0, time * 0.05)), fbm(q + float2(5.2, 1.3 - time * 0.04)));
        return fbm(q + 2.3 * warp);
    }

    /// Signed distance, in points, from the crescent; its line wanders slowly with a broad field, so
    /// it sways instead of standing rigid.
    float arcOffset(float2 point, float2 size, float time) {
        float top = size.y * crest + breath * sin(time * 0.6);
        float2 radii = size * reach;
        float2 relative = (point - float2(size.x * 0.5, top + radii.y)) / radii;
        float wander = (fbm(float2(point.x / 420.0 + time * 0.06, 7.3)) - 0.5) * sway;
        return (length(relative) - 1.0) * radii.y + wander;
    }

    /// How much of the wind shows at `offset` from the crescent, before the field modulates it:
    /// full at the crest, finer toward the ends, which dissolve before the page's sides.
    float envelope(float offset, float gust, float across) {
        float taper = 1.0 - across * across;
        float width = band * (0.3 + 0.7 * taper) * (0.75 + 0.5 * gust);
        float line = exp(-(offset / width) * (offset / width));
        float above = offset < 0.0 ? sprayStrength * exp(offset / spray) : hazeStrength * exp(-offset / haze);
        return max(line, above) * (1.0 - smoothstep(0.55, 0.97, across));
    }

    /// How far a dot has grown `since` seconds after the gust passed it: 0 before, 1 once settled,
    /// with a small pop past full size on the way.
    float growth(float since, float seed) {
        float local = saturate((since - seed * growScatter) / growTime) - 1.0;
        return 1.0 + (overshoot + 1.0) * local * local * local + overshoot * local * local;
    }
}

/// `size` is the drawn area in points, `pixel` one pixel in points, `time` the wind's own time.
/// The gust leaves `origin`, below the page, at `speed` points per second; `intro` is the time since
/// the page appeared, in seconds. Its light travels to `target`, the control bar's center. The dots
/// are `ink`, the densest move toward `core`, and the light is `light`. Returns a premultiplied color.
[[ stitchable ]] half4 windArc(float2 position, half4 color, float2 size, float time, float2 origin, float2 target,
                               float intro, float speed, half4 ink, half4 core, half4 light, float pixel) {
    // The light: a soft glow rising from below the page toward the bar, shrinking as it closes in,
    // then fading on the bar as the bar's own light takes over.
    float travel = length(target - origin) / speed;
    half4 glow = half4(0);
    if (intro < travel + 4.0 * lightFade) {
        float progress = saturate(intro / travel);
        float eased = 1.0 - pow(1.0 - progress, 3.0);
        float2 center = mix(origin, target, eased);
        float radius = mix(size.x * 0.5, size.x * 0.2, eased);
        float2 toCenter = position - center;
        float presence = intro < travel ? smoothstep(0.0, 0.35, progress) : exp(-(intro - travel) / lightFade);
        // A hair of noise keeps the faint gradient from banding.
        float strength = max(0.0, lightStrength * presence * exp(-dot(toCenter, toCenter) / (radius * radius))
            + (hash(position * 7.0) - 0.5) / 255.0);
        glow = half4(light.rgb * half(strength), half(strength));
    }

    // Behind the gust's ragged front, the air swings back and forth as it settles: the whole texture
    // is pushed away from the origin and returns.
    float2 away = position - origin;
    float2 heading = away / max(length(away), 1.0);
    float jag = (fbm(float2(atan2(heading.x, -heading.y) * 4.0, 3.1)) - 0.5) * ragged;
    float passed = intro - (length(away) + jag) / speed;
    if (passed > 0.0) {
        position -= heading * blast * exp(-passed / settleTime) * sin(passed * 6.2831853 / swingTime + 0.6);
    }

    float2 cell = floor(position / pitch);
    float2 center = (cell + 0.5) * pitch;
    // Points above the crescent have a negative offset, points inside it a positive one.
    float offset = -arcOffset(center, size, time);
    float across = abs(2.0 * center.x / size.x - 1.0);
    float since = intro - (length(center - origin) + jag) / speed;
    float grown = max(growth(since, hash(cell + 91.0)), 0.0) * (1.0 + swell * exp(-(since / swellTime) * (since / swellTime)));

    // Skip the field wherever even the strongest gust could not reach this pixel.
    float distance = length(position - center);
    if (sqrt(min(1.0, envelope(offset, 1.0, across) * 1.25)) * pitch * dotScale * grown + pixel < distance) { return glow; }

    float field = wind(center, time);
    float gust = smoothstep(0.3, 0.7, field);
    float darkness = min(1.0, envelope(offset, gust, across) * (0.45 + 0.8 * gust));
    // Continuous down to zero: a hard threshold would cut the wind with stepped edges.
    float visible = saturate((darkness - faintest) / (1.0 - faintest));
    float radius = sqrt(visible) * pitch * dotScale * grown;
    float coverage = saturate((radius - distance) / pixel + 0.5);
    if (coverage <= 0.0) { return glow; }

    half3 tone = mix(ink.rgb, core.rgb, half(smoothstep(0.55, 1.0, darkness)));
    half alpha = half(coverage * (0.3 + 0.6 * visible));
    return half4(tone * alpha, alpha) + glow * (1.0h - alpha);
}
