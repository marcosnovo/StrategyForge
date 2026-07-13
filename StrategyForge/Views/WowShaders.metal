//
//  WowShaders.metal
//  StrategyForge
//
//  `liquidLight` — a glossy coral↔teal light ORB: a soft radial body with a moving
//  specular highlight (glass sphere), a low-frequency flowing coral↔teal field, a
//  warm amber centre and a teal halo ring, fading cleanly at the edges. Verified on a
//  CPU port before shipping. Used via SwiftUI `.colorEffect`.
//

#include <metal_stdlib>
using namespace metal;

static float hashN(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hashN(i), b = hashN(i + float2(1, 0));
    float c = hashN(i + float2(0, 1)), d = hashN(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * vnoise(p); p *= 2.0; a *= 0.5; }
    return v;
}

[[ stitchable ]] half4 liquidLight(float2 pos, half4 color, float2 size, float time, float prog) {
    float2 uv = pos / size;
    float2 c = uv - 0.5; c.x *= size.x / size.y;
    float d = length(c);

    float env  = smoothstep(0.0, 0.14, prog) * (1.0 - smoothstep(0.72, 1.0, prog));
    float grow = 0.5 + 0.5 * smoothstep(0.0, 0.55, prog);
    float rad  = d / grow;

    // Low-frequency flowing coral↔teal field (smooth blobs, not veins).
    float wx = fbm(float2(uv.x * 1.7 + time * 0.12, uv.y * 1.7));
    float wy = fbm(float2(uv.x * 1.7 + 5.2, uv.y * 1.7 + time * 0.10));
    float m  = fbm(float2(uv.x * 1.7 + wx * 1.3, uv.y * 1.7 + wy * 1.3 + time * 0.08));

    float core = exp(-rad * rad * 2.7);                          // soft orb body
    float2 hl = float2(-0.16 + 0.06 * cos(time * 0.9), -0.18 + 0.06 * sin(time * 0.9));
    float hd = length(c - hl);
    float spec = exp(-hd * hd * 26.0) * (1.0 - smoothstep(0.2, 1.0, rad));   // moving gloss
    float tealHalo = smoothstep(0.15, 0.5, rad) * (1.0 - smoothstep(0.5, 0.85, rad));
    float bright = clamp(core * 0.95 + spec * 0.9 + tealHalo * 0.45, 0.0, 1.6);

    half3 coral = half3(0.970, 0.420, 0.280);
    half3 teal  = half3(0.100, 0.800, 0.700);
    half3 amber = half3(1.000, 0.660, 0.340);
    half3 white = half3(1.000, 0.980, 0.950);
    float mm = clamp((m - 0.2) * 1.6, 0.0, 1.0);
    half3 col = mix(coral, teal, half(mm * 0.85));
    col = mix(col, amber, half(core * 0.32));                    // warm centre
    col = mix(col, white, half(min(1.0, spec)));                 // specular
    col = mix(col, teal, half(min(1.0, tealHalo) * 0.7));        // teal halo ring

    float vign = 1.0 - smoothstep(0.05, 1.1, rad);
    half a = half(bright * env * vign);
    return half4(col, a);
}
