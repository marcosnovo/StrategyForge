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

    // Centred light bloom that FADES to transparent by the edges (a focused burst,
    // not a full-frame texture). The swell breathes with the envelope.
    float pulse = 0.55 + 0.45 * sin(prog * 3.14159);
    float bloom = smoothstep(0.58, 0.0, d);          // 1 at centre → 0 at rim
    float core  = pow(bloom, 2.2) * 1.5 * pulse;     // hot centre

    // Domain-warped caustic FILAMENTS — thin bright threads, only visible where the
    // bloom is (so the edges stay clean instead of a green marble).
    float2 q = float2(fbm(uv * 3.0 + time * 0.15), fbm(uv * 3.0 + 5.2 + time * 0.12));
    float2 r = float2(fbm(uv * 3.0 + 4.0 * q + time * 0.20), fbm(uv * 3.0 + 4.0 * q + 9.1));
    float n = fbm(uv * 4.0 + 4.0 * r);
    float caustic = pow(1.0 - abs(0.5 - n) * 2.0, 6.0);   // thin ridges
    float veins = caustic * bloom;
    float spec  = pow(caustic, 10.0) * bloom;             // sparkle

    float bright = clamp(core + veins * 0.55 + spec * 1.6, 0.0, 1.9);

    // Coral-forward: white-hot centre → coral → amber sparkle → a whisper of teal
    // only at the outer rim.
    half3 white = half3(1.000, 0.950, 0.900);
    half3 coral = half3(0.960, 0.420, 0.280);
    half3 amber = half3(1.000, 0.700, 0.300);
    half3 teal  = half3(0.120, 0.800, 0.700);
    half3 col = mix(coral, white, half(clamp(core * 0.6, 0.0, 1.0)));
    col = mix(col, amber, half(spec));
    col = mix(col, teal, half(smoothstep(0.34, 0.56, d)) * 0.45);

    float env = smoothstep(0.0, 0.1, prog) * (1.0 - smoothstep(0.72, 1.0, prog));
    half a = half(bright * env * bloom);              // vignette the alpha too
    return half4(col, a);
}
