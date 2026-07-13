//
//  WowShaders.metal
//  StrategyForge
//
//  `liquidLight` — domain-warped fbm caustics (Inigo-Quilez-style "warp the noise
//  with more noise") + specular sparkle + radial bloom, tinted coral→amber→teal.
//  Real per-pixel light for the Liquid Light celebration, via `.colorEffect`.
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
    for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.02; a *= 0.5; }
    return v;
}

[[ stitchable ]] half4 liquidLight(float2 pos, half4 color, float2 size, float time, float prog) {
    float2 uv = pos / size;
    float2 c = uv - 0.5; c.x *= size.x / size.y;
    float d = length(c);

    // Domain warp: noise warped by noise warped by noise → liquid caustic ridges.
    float2 q = float2(fbm(uv * 3.0 + time * 0.15), fbm(uv * 3.0 + 5.2 + time * 0.12));
    float2 r = float2(fbm(uv * 3.0 + 4.0 * q + time * 0.20), fbm(uv * 3.0 + 4.0 * q + 9.1));
    float n = fbm(uv * 4.0 + 4.0 * r);
    float caustic = pow(1.0 - abs(0.5 - n) * 2.0, 3.0);   // bright veins
    float spec = pow(caustic, 8.0);                        // sparkle highlights

    float swell = smoothstep(0.62, 0.0, d) * (0.4 + 0.6 * sin(prog * 3.14159));
    float bright = clamp(caustic * 0.8 + spec * 1.3 + swell * 0.7, 0.0, 1.7);

    half3 coral = half3(0.941, 0.376, 0.227);
    half3 amber = half3(1.000, 0.660, 0.250);
    half3 teal  = half3(0.078, 0.761, 0.671);
    half3 col = mix(coral, teal, half(clamp(d * 1.3, 0.0, 1.0)));   // core coral → rim teal
    col = mix(col, amber, half(spec) * 0.7);                        // hot amber sparkle

    float env = smoothstep(0.0, 0.12, prog) * (1.0 - smoothstep(0.72, 1.0, prog));
    half a = half(bright * env);
    return half4(col, a);
}
