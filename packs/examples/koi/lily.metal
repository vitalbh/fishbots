// A lily pad floating at the surface, seen a little from above: a round leaf with its notch, veins from the middle,
// its stem hanging down into the water; some (by seed) carry a lotus flower. The surface is at c.y = 0.2.
float4 draw_lily(float2 c, float t, float glow, float4 col, float4 extra) {
    float seed = extra.y;
    float2 p = c - float2(0.0, 0.2);
    // the pad: a flat ellipse (a round leaf seen almost edge-on) with a little thickness under it, and its V notch
    // opening toward us
    float2 q = p / float2(0.92, 0.2);
    float top = (length(q) - 1.0) * 0.2;
    float side = (length((p + float2(0.0, 0.035)) / float2(0.92, 0.2)) - 1.0) * 0.2;
    float nx = 0.25 + 0.3 * fract(seed * 3.7);
    float notch = sd_tri(p, float2(nx - 0.05, -0.02), float2(nx - 0.12, -0.3), float2(nx + 0.12, -0.3));
    float leaf = max(min(top, side), -notch);
    float rim = top;
    // the stem, down into the water, swaying
    float sx = sin(t * 0.4 + seed * 9.0) * 0.06 * (-p.y);
    float stem = max(abs(p.x - 0.05 - sx) - 0.025, max(p.y + 0.02, -p.y - 1.3));
    // a lotus flower on some of them: a cup of pink petals on a short stalk
    bool flower = fract(seed * 7.13) > 0.55;
    float petals = 1e3;
    float2 fp = p - float2(-0.15, 0.42);
    if (flower) {
        for (int i = -2; i <= 2; i++) {
            float a = float(i) * 0.38;
            float2 pq = fp - float2(sin(a) * 0.06, -0.12);
            pq = float2(pq.x * cos(a) - pq.y * sin(a), pq.x * sin(a) + pq.y * cos(a));
            petals = min(petals, (length((pq - float2(0.0, 0.17)) / float2(0.1 - 0.015 * abs(float(i)), 0.22)) - 1.0) * 0.1);
        }
        petals = min(petals, max(abs(p.x + 0.15) - 0.018, max(p.y - 0.32, -p.y + 0.02)));
    }
    float d = min(min(leaf, stem), petals);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 green = col.rgb;
    float3 c3;
    if (petals < 0.0 && petals < leaf) {
        float h = clamp((fp.y + 0.12) / 0.4, 0.0, 1.0);
        c3 = mix(float3(1.0, 0.92, 0.9), float3(0.95, 0.5, 0.65), smoothstep(0.3, 1.0, h));
        c3 *= 0.8 + 0.25 * cos(atan2(fp.x, fp.y + 0.15) * 10.0);
        if (abs(p.x + 0.15) < 0.018 && p.y < 0.32) c3 = green * 0.8;
    } else if (leaf < 0.0) {
        // the top of the leaf: veins radiating from the middle, lighter toward the light, a darker rim
        float veins = 0.5 + 0.5 * cos(atan2(q.y, q.x) * 18.0);
        c3 = green * (0.85 + 0.15 * veins) * (0.8 + 0.4 * smoothstep(-0.15, 0.1, p.y));
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -rim)) * 0.35;
        c3 += float3(1.0) * pow(max(0.0, 1.0 - length((p - float2(-0.3, 0.05)) / float2(0.35, 0.06))), 3.0) * 0.25;   // wet sheen
        if (p.y < -0.04) c3 = green * float3(0.6, 0.45, 0.45);                     // the reddish underside
    } else {
        c3 = green * float3(0.55, 0.5, 0.4) * (0.7 + 0.3 * smoothstep(-1.3, 0.0, p.y));
        a *= 0.55 + 0.45 * smoothstep(-1.3, -0.3, p.y);                            // fading down in the water
    }
    return float4(c3 * a, a);
}
