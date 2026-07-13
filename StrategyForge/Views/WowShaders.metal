//
//  WowShaders.metal
//  StrategyForge
//
//  Metal shaders for the "wow" candidates. `liquidLight` renders a flowing
//  caustic coral↔teal light field (real per-pixel light, not flat shapes) for the
//  Liquid Light celebration. Used via SwiftUI `.colorEffect(ShaderLibrary.…)`.
//

#include <metal_stdlib>
using namespace metal;

// Flowing caustic light: summed, drifting sine lobes make bright "veins" that ripple
// like light through water, tinted coral→teal. `prog` (0…1) is the reveal envelope.
[[ stitchable ]] half4 liquidLight(float2 pos, half4 color, float2 size, float time, float prog) {
    float2 uv = pos / size;
    float2 c = uv - 0.5;
    float d = length(c);

    // Layered drifting field for the caustic veins.
    float2 p = uv * 3.2;
    float v = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        p += float2(sin(time * 0.7 + fi * 1.3), cos(time * 0.6 + fi));
        v += sin(p.x + time) * cos(p.y - time * 0.9);
    }
    v = v / 4.0;                                   // -1…1
    float veins = pow(max(0.0, v * 0.5 + 0.5), 3.5);

    // A soft radial swell that grows then eases with the envelope.
    float swell = smoothstep(0.55, 0.0, d) * (0.4 + 0.6 * sin(prog * 3.14159));

    float bright = clamp(veins * 0.9 + swell * 0.8, 0.0, 1.4);

    // Coral core → teal rim, modulated by the veins.
    half3 coral = half3(0.941, 0.376, 0.227);
    half3 teal  = half3(0.078, 0.761, 0.671);
    half3 col = mix(coral, teal, half(clamp(d * 1.4 + v * 0.25, 0.0, 1.0)));

    // Envelope: fade in fast, hold, fade out.
    float env = smoothstep(0.0, 0.15, prog) * (1.0 - smoothstep(0.7, 1.0, prog));
    half a = half(min(1.0, bright * env));
    return half4(col, a);                          // straight (composited additively)
}
