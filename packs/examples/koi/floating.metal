// Tōrō nagashi: a paper lantern floating on the water, a presence plugins can use ("kind": "floating-lantern"). Its
// light follows the state (extra.w): warm when ok, flickering while busy, red on error, pulsing while it waits for you.
// The water line is at c.y ≈ 0.12 / extent.y (the base sits in it).
float4 draw_koi_floating_lantern(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    int state = int(extra.w + 0.5);
    float base = sd_box(p - float2(0.0, -0.05), float2(0.42, 0.08), 0.02);                      // the wooden float
    float paper = sd_box(p - float2(0.0, 0.38), float2(0.32 - 0.03 * (p.y - 0.38), 0.3), 0.04);  // the paper box
    float roof = sd_tri(p, float2(-0.42, 0.66), float2(0.42, 0.66), float2(0.0, 0.86)) - 0.01;
    float d = min(min(base, paper), roof);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // the light inside, by state
    float3 lightC = state == 5 ? float3(1.0, 0.35, 0.25) : state == 2 ? float3(1.0, 0.85, 0.45) : float3(1.0, 0.78, 0.42);
    float k = state == 1 ? 0.8 + 0.2 * sin(phase * 9.0) * sin(phase * 4.3)
            : state == 2 ? 0.6 + 0.4 * (0.5 + 0.5 * sin(phase * 3.0))
            : state == 0 ? 0.35 : 0.85;
    float3 c3;
    if (paper < min(base, roof)) {
        float2 q = (p - float2(0.0, 0.38)) / float2(0.32, 0.3);
        float core = exp(-dot(q, q) * 1.6);
        c3 = mix(float3(0.92, 0.88, 0.8) * 0.5, lightC, core * k) * (0.7 + 0.5 * k);
        c3 *= 1.0 - 0.25 * step(0.92, fract(q.x * 1.5 + 0.5)) * step(abs(q.y), 0.9);       // the paper's frame
        c3 = mix(c3, col.rgb * 0.5, (1.0 - smoothstep(0.03, 0.06, abs(q.y - 0.1))) * 0.6);   // a painted band in its color
    } else if (roof < base) {
        c3 = float3(0.3, 0.22, 0.16) * (0.8 + 0.3 * smoothstep(0.66, 0.86, p.y));
    } else {
        c3 = float3(0.45, 0.32, 0.2) * (0.7 + 0.3 * smoothstep(-0.13, 0.03, p.y));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    // its light on the water around it and its reflection below
    float halo = exp(-length((p - float2(0.0, 0.35)) / float2(0.9, 0.7)) * 2.5) * k * (1.0 - a) * 0.5;
    float refl = exp(-abs(p.x) * 6.0) * smoothstep(-0.12, -0.6, p.y) * (1.0 - smoothstep(-0.6, -0.95, p.y)) * k * 0.35 * (1.0 - a);
    float g = halo + refl * (0.7 + 0.3 * sin(p.y * 40.0 + phase * 2.0));
    return float4(c3 * a + lightC * g, a + g * 0.6);
}
