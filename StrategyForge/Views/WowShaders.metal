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

// ── Coral Reef ──────────────────────────────────────────────────────────────
// A stylised underwater reef that GROWS: teal water with dappled caustics + god
// rays, layered branching coral colonies (the CoralMark motif) rising from a
// seabed with depth (dim teal-tinted colonies behind, bright coral in front),
// and rising bubbles. `prog` (0…1) drives growth + fade.

static float sdSeg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// One coral colony's [ax,ay,bx,by,th0,th1] branches in local space (y: 0 top → 1 base).
constant float BR[9][6] = {
    {0, 1, 0, 0.55, 0.055, 0.05},
    {0, 0.62, -0.20, 0.30, 0.045, 0.02}, {-0.20, 0.32, -0.30, 0.10, 0.03, 0.010}, {-0.20, 0.34, -0.09, 0.13, 0.028, 0.010},
    {0, 0.60, 0.22, 0.28, 0.045, 0.02},  {0.22, 0.30, 0.33, 0.08, 0.03, 0.010},   {0.22, 0.32, 0.11, 0.11, 0.028, 0.010},
    {0, 0.70, -0.02, 0.42, 0.04, 0.013}, {0, 0.70, 0.05, 0.40, 0.04, 0.013},
};

// Returns (coverage, tipness) for the colony at cx / scale / flip.
static float2 coralField(float2 uv, float cx, float scale, float grow, float time, float flip) {
    float best = 9.0, tip = 0.0;
    float sway = sin(time * 1.3 + cx * 7.0) * 0.02;
    for (int i = 0; i < 9; i++) {
        float ay = 1.0 - BR[i][1] * scale * grow, by = 1.0 - BR[i][3] * scale * grow;
        float ax = cx + flip * BR[i][0] * scale + sway * (1.0 - BR[i][1]);
        float bx = cx + flip * BR[i][2] * scale + sway * (1.0 - BR[i][3]);
        float d = sdSeg(uv, float2(ax, ay), float2(bx, by)) - (BR[i][4] + BR[i][5]) * 0.5 * scale;
        if (d < best) { best = d; tip = 1.0 - BR[i][3]; }
    }
    return float2(smoothstep(0.012, -0.004, best), tip);
}

// (cx, scale, flip, depthDim) per colony — back rows dim/small, front bright/big.
constant float4 BUSH[7] = {
    float4(0.18, 0.34,  1, 0.45), float4(0.83, 0.36, -1, 0.45),
    float4(0.40, 0.40, -1, 0.60), float4(0.62, 0.42,  1, 0.60),
    float4(0.30, 0.52,  1, 0.85), float4(0.72, 0.50, -1, 0.85),
    float4(0.50, 0.66,  1, 1.00),
};

[[ stitchable ]] half4 coralReef(float2 pos, half4 color, float2 size, float time, float prog) {
    float2 uv = pos / size;
    float aspect = size.x / size.y;
    float3 deep = float3(0.02, 0.07, 0.10), water = float3(0.05, 0.44, 0.44);
    float3 c = mix(deep, water, 1.0 - uv.y);

    // Caustics from above + god rays.
    float cau = pow(max(0.0, fbm(float2(uv.x * 5.0 + time * 0.3, uv.y * 5.0 - time * 0.5))), 1.6) * (1.0 - uv.y) * 0.55;
    c += float3(0.5, 0.95, 0.85) * cau;
    float ray = pow(max(0.0, 0.5 + 0.5 * sin(uv.x * 9.0 - 1.0)), 6.0) * (1.0 - uv.y) * 0.14;
    c += float3(0.4, 0.75, 0.72) * ray;

    // Seabed.
    float fl = smoothstep(0.85, 0.95, uv.y);
    c = mix(c, float3(0.10, 0.14, 0.14), fl * 0.8);

    // Coral colonies (back → front).
    float grow = smoothstep(0.0, 0.6, prog);
    for (int i = 0; i < 7; i++) {
        float4 bh = BUSH[i];
        float2 cf = coralField(uv, bh.x, bh.y, grow, time, bh.z);
        float cov = cf.x, tip = cf.y, dim = bh.w;
        if (cov > 0.001) {
            float3 base = float3(0.72, 0.22, 0.12), tipc = float3(1.0, 0.58, 0.44);
            float3 cc = mix(base, tipc, tip);
            cc = mix(cc, float3(1.0, 0.7, 0.4), tip * tip * 0.2);       // amber tips
            cc = mix(water, cc, dim);                                  // depth fade
            c = mix(c, cc, cov * dim);
        }
    }

    // Rising bubbles.
    for (int i = 0; i < 10; i++) {
        float seed = float(i) / 10.0;
        float bxp = fract(seed * 7.3), speed = 0.14 + seed * 0.12;
        float byp = fract(1.2 - (time * speed + seed)), wob = sin(time * 2.0 + seed * 10.0) * 0.012;
        float2 dd = float2((uv.x - (bxp + wob)) * aspect, uv.y - byp);
        float br = 0.005 + seed * 0.006;
        float b = smoothstep(br, br * 0.4, length(dd)) * 0.5 * smoothstep(0.0, 0.12, byp);
        c += float3(0.6, 0.9, 0.9) * b;
    }

    float env = smoothstep(0.0, 0.12, prog) * (1.0 - smoothstep(0.82, 1.0, prog));
    return half4(half3(min(c, 1.0)), half(env));
}
