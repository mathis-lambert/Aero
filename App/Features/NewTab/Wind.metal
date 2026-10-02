// The New Tab page's wind: the mistral field of Scripts/generate-app-icon.swift in a crescent near the
// bottom edge, drawn as a halftone of round dots whose size and opacity follow its darkness.
// As the page appears a gust rises from below it: behind its ragged front the dots grow
// in, lit for a moment, and the air swings back. Keystrokes send rings through the dots.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

namespace {
    // The dots, on a hexagonal lattice: every row is offset by half a pitch.
    constant float pitch = 5.0;            // distance between neighboring dots, in points
    constant float rowStep = 4.330127;     // pitch * sqrt(3) / 2
    constant float dotScale = 0.46;        // largest dot radius, as a share of the pitch: dots never touch
    constant float faintest = 0.08;        // dots shrink to nothing at this darkness, so the page never looks dusty
    constant float grain = 0.2;            // how much a fine field varies the dots' size, so no two areas repeat
    constant float flicker = 0.15;         // how much it varies their opacity

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
    constant float margin = 40.0;          // what the sway, the gust and the rings can add to a point's offset

    // The wind.
    constant float windScale = 300.0;      // wavelength of the field
    constant float drift = 0.09;           // field widths per second along the wind
    constant float2 windDirection = float2(0.9135455, 0.4067366); // 24°, rising to the right

    // The gust. Its front is fast at first and slows as it spreads; each point then follows its own timings.
    constant float ragged = 90.0;          // how uneven its front is, in points; matches WindArc.ragged
    constant float blast = 9.0;            // how far it pushes the texture, in points
    constant float settleTime = 0.45;      // how long the push takes to die out, in seconds
    constant float swingTime = 0.7;        // period of the push's damped swing, in seconds
    constant float growTime = 0.45;        // how long a dot takes to grow in, in seconds
    constant float growScatter = 0.14;     // how much each dot's growth is delayed at most, in seconds
    constant float overshoot = 1.4;        // the growth's back-out easing, for a pop past full size
    constant float pop = 0.3;              // how much larger dots are right as the front passes
    constant float popTime = 0.18;         // how long that lasts, in seconds
    constant float litTime = 0.55;         // how long a dot keeps the front's light, in seconds
    constant float litStrength = 0.8;

    // The rings a keystroke sends.
    constant float ringSpeed = 360.0;      // in points per second
    constant float ringWidth = 24.0;       // half-width of the ring, in points
    constant float ringPush = 3.2;         // how far the ring moves the dots, in points
    constant float ringSwell = 0.3;        // how much larger dots are on the ring
    constant float ringLife = 1.2;         // in seconds; matches WindArc.rippleLife
    constant float ringReach = 620.0;      // the ring has faded out at this distance, in points

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

    /// Signed distance, in points, from the crescent's ellipse, without its wandering.
    float ellipseOffset(float2 point, float2 size, float time) {
        float top = size.y * crest + breath * sin(time * 0.6);
        float2 radii = size * reach;
        float2 relative = (point - float2(size.x * 0.5, top + radii.y)) / radii;
        return (length(relative) - 1.0) * radii.y;
    }

    /// The crescent's line wanders slowly with a broad field, so it sways instead of standing rigid.
    float arcOffset(float2 point, float2 size, float time) {
        float wander = (fbm(float2(point.x / 420.0 + time * 0.06, 7.3)) - 0.5) * sway;
        return ellipseOffset(point, size, time) + wander;
    }

    /// How much of the wind shows at `offset` from the crescent (negative above it), before the field
    /// modulates it: full at the crest, finer toward the ends, which dissolve before the page's sides.
    float envelope(float offset, float gust, float across) {
        float taper = 1.0 - across * across;
        float width = band * (0.3 + 0.7 * taper) * (0.75 + 0.5 * gust);
        float line = exp(-(offset / width) * (offset / width));
        float side = offset < 0.0 ? sprayStrength * exp(offset / spray) : hazeStrength * exp(-offset / haze);
        return max(line, side) * (1.0 - smoothstep(0.55, 0.97, across));
    }

    /// How far a dot has grown `since` seconds after the front passed it: 0 before, 1 once settled,
    /// with a pop past full size on the way.
    float growth(float since, float seed) {
        float local = saturate((since - seed * growScatter) / growTime) - 1.0;
        return 1.0 + (overshoot + 1.0) * local * local * local + overshoot * local * local;
    }

    /// The nearest point of the hexagonal lattice.
    float2 nearestDot(float2 position) {
        float2 cell = float2(pitch, 2.0 * rowStep);
        float2 shift = float2(0.5 * pitch, rowStep);
        float2 even = (floor(position / cell) + 0.5) * cell;
        float2 odd = (floor((position - shift) / cell) + 0.5) * cell + shift;
        return distance_squared(position, even) < distance_squared(position, odd) ? even : odd;
    }
}

/// `size` is the drawn area in points, `pixel` one pixel in points, `time` the wind's own time. The gust
/// leaves `origin`, below the page's center, and its front covers `spread` points in `duration`
/// seconds, easing out; `intro` is the time since the page appeared. `rings` holds, for each keystroke,
/// the ring's origin and age as three values. The dots are `ink`, the densest move toward `core`, and the
/// front lights them with `light`. Returns a premultiplied color.
[[ stitchable ]] half4 windArc(float2 position, half4 color, float2 size, float time, float2 origin,
                               float intro, float duration, float spread, device const float *rings, int ringValues,
                               half4 ink, half4 core, half4 light, float pixel) {
    // Nothing shows far from the crescent: leave before any noise is computed.
    float rough = -ellipseOffset(position, size, time);
    float roughAcross = abs(2.0 * position.x / size.x - 1.0);
    if (envelope(sign(rough) * max(abs(rough) - margin, 0.0), 1.0, roughAcross) * 1.25 < faintest) { return half4(0); }

    // Behind the gust's ragged front the air swings back and forth as it settles: the whole texture is
    // pushed away from the origin and returns.
    float2 away = position - origin;
    float2 heading = away / max(length(away), 1.0);
    bool rising = intro < duration + 2.0;
    float jag = rising ? (fbm(float2(atan2(heading.x, -heading.y) * 4.0, 3.1)) - 0.5) * ragged : 0.0;
    float passed = intro - duration * (1.0 - pow(1.0 - saturate((length(away) + jag) / spread), 1.0 / 3.0));
    if (rising && passed > 0.0) {
        position -= heading * blast * exp(-passed / settleTime) * sin(passed * 6.2831853 / swingTime + 0.6);
    }

    // Each ring pushes the dots ahead of it and draws them back behind, and swells those it crosses.
    float ringGrowth = 0.0;
    for (int index = 0; index + 2 < ringValues; index += 3) {
        float age = rings[index + 2];
        if (age >= ringLife) { continue; }
        float2 fromRing = position - float2(rings[index], rings[index + 1]);
        float distanceToRing = max(length(fromRing), 1.0);
        float front = (distanceToRing - age * ringSpeed) / ringWidth;
        if (abs(front) > 3.0) { continue; }
        float strength = exp(-age / (0.45 * ringLife)) * smoothstep(0.0, 0.08, age) * saturate(1.0 - distanceToRing / ringReach);
        float profile = exp(-front * front);
        position -= fromRing / distanceToRing * ringPush * strength * front * profile * 1.65;
        ringGrowth += ringSwell * strength * profile;
    }

    float2 center = nearestDot(position);
    float since = intro - duration * (1.0 - pow(1.0 - saturate((distance(center, origin) + jag) / spread), 1.0 / 3.0));
    float seed = hash(center * 1.7 + 91.0);
    float grown = max(growth(since, seed), 0.0) * (1.0 + pop * exp(-(since / popTime) * (since / popTime))) + ringGrowth;
    float toDot = length(position - center);
    // A dot never reaches past its cell: the far corners of a cell skip the noise.
    if (toDot > 0.5 * pitch + pixel) { return half4(0); }
    float offset = -arcOffset(center, size, time);
    float across = abs(2.0 * center.x / size.x - 1.0);
    // Skip the field wherever even the strongest gust could not reach this pixel.
    float reachable = sqrt(min(1.0, envelope(offset, 1.0, across) * 1.25)) * pitch * dotScale * grown * (1.0 + 0.5 * grain);
    if (reachable + pixel < toDot) { return half4(0); }
    float gust = smoothstep(0.3, 0.7, wind(center, time));
    float darkness = min(1.0, envelope(offset, gust, across) * (0.45 + 0.8 * gust));
    // Continuous down to zero: a hard threshold would cut the wind with stepped edges.
    float visible = saturate((darkness - faintest) / (1.0 - faintest));
    float fine = noise(center / 16.0 + float2(time * 0.25, 0.0)) - 0.5;
    float radius = min(sqrt(visible) * pitch * dotScale * grown * (1.0 + grain * fine), 0.5 * pitch);
    float coverage = saturate((radius - toDot) / pixel + 0.5);
    if (coverage <= 0.0) { return half4(0); }

    // The front's light stays a moment on the dots it reaches, then they settle into their tone.
    float lit = rising && since > 0.0 ? litStrength * exp(-since / litTime) : 0.0;
    half3 tone = mix(ink.rgb, core.rgb, half(smoothstep(0.55, 1.0, darkness)));
    tone = mix(tone, light.rgb, half(lit));
    half alpha = half(coverage * saturate((0.25 + 0.7 * visible) * (1.0 + flicker * 2.0 * fine) + 0.35 * lit));
    return half4(tone * alpha, alpha);
}
