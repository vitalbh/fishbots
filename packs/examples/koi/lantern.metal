// Tōrō, a stone lantern standing on the sand: a base, a post, the firebox with a window, a curved roof and a jewel on
// top. At night its window glows (glow) and lights the stone around it. extra.y: a seed for the moss and the wear.
float4 draw_lantern(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float base = sd_box(p - float2(0.0, -0.9), float2(0.62, 0.1), 0.04);
    float post = sd_box(p - float2(0.0, -0.55), float2(0.2, 0.26), 0.03);
    float plat = sd_box(p - float2(0.0, -0.24), float2(0.6, 0.06), 0.03);
    float box = sd_box(p - float2(0.0, 0.03), float2(0.42, 0.22), 0.03);
    // the roof: wide, with tips curving up
    float ry = p.y - 0.3;
    float roofW = 0.86 - ry * 1.6 + 0.08 * smoothstep(0.5, 0.9, abs(p.x));
    float roof = max(abs(p.x) - roofW * 0.95, max(-ry, ry - 0.24 + 0.1 * smoothstep(0.55, 0.9, abs(p.x))));
    roof = max(roof, -(ry + 0.05 - 0.12 * smoothstep(0.45, 0.95, abs(p.x))) * 1.0);
    float jewel = min(length(p - float2(0.0, 0.66)) - 0.08, sd_box(p - float2(0.0, 0.57), float2(0.04, 0.04), 0.01));
    float d = min(min(min(base, post), min(plat, box)), min(roof, jewel));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // the window and the light behind it
    float win = sd_box(p - float2(0.0, 0.03), float2(0.2, 0.13), 0.02);
    float inWin = 1.0 - smoothstep(-aa, aa, win);
    float bars = step(abs(p.x), 0.015) * inWin;
    // stone: weathered, with moss on the upper faces
    float n = vnoise(p * 6.0 + extra.y * 20.0) * 0.6 + vnoise(p * 17.0) * 0.4;
    float3 stone = col.rgb * (0.75 + 0.35 * n);
    float up = smoothstep(0.02, -0.02, max(roof, -1.0)) * smoothstep(0.15, 0.3, ry);
    stone = mix(stone, float3(0.32, 0.42, 0.26) * dot(col.rgb, float3(0.7)), smoothstep(0.55, 0.75, n + up * 0.4) * 0.6);
    // light from above: tops bright, undersides dark (under the roof, under the platform)
    float shade = 0.75 + 0.3 * smoothstep(-1.0, 1.0, p.y);
    shade *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, -(p.y - 0.28))) * step(abs(p.x), 0.45) * step(p.y, 0.3) * step(0.2, p.y);
    float3 c3 = stone * shade;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    // the glow: warm light in the window, spilling onto the stone around it
    float3 warm = float3(1.0, 0.72, 0.32);
    float spill = exp(-max(win, 0.0) * 9.0) * glow;
    c3 += warm * spill * 0.35 * (1.0 - inWin);
    float3 lit = mix(float3(0.08, 0.06, 0.05), warm * (0.8 + 0.6 * glow), clamp(0.15 + glow, 0.0, 1.0));
    lit *= 0.9 + 0.1 * sin(t * 7.0 + extra.y * 30.0) * glow;                    // the flame flickers
    c3 = mix(c3, lit, inWin * (1.0 - bars));
    c3 = mix(c3, stone * 0.5, bars);
    return float4(c3 * a, a);
}

// A river stone on the sand: smooth, rounded, wet (a soft highlight), in browns and grays (extra.y varies it).
float4 draw_koi_stone(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.6);
    float2 q = (p - float2(0.0, -0.22)) / float2(0.85, 0.36 + 0.08 * extra.y);
    float d = (length(q) - 1.0) * 0.36;
    d = max(d, -(p.y + 0.55));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
    float3 base = mix(float3(0.42, 0.38, 0.33), float3(0.55, 0.52, 0.48), extra.y) * mix(float3(1.0), col.rgb * 1.6, 0.3);
    float3 c3 = base * (0.45 + 0.7 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5)))));
    c3 += float3(1.0) * pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0, 0, 1))), 24.0) * 0.45;
    c3 *= 0.9 + 0.15 * vnoise(p * 14.0 + extra.y * 9.0);
    return float4(c3 * a, a);
}

// A small pond snail's shell lying on the sand: a brown spiral, glossy.
float4 draw_koi_snail_shell(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.75);
    float2 q = p - float2(-0.05, -0.15);
    float r = length(q / float2(1.0, 0.85));
    float d = max((r - 0.55) * 0.5, -(p.y + 0.62));
    d = min(d, sd_tri(p, float2(0.3, -0.05), float2(0.75, -0.5), float2(0.2, -0.55)) - 0.04);   // the opening's lip
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float spiral = fract(log(max(r, 0.02)) * 2.5 - atan2(q.y, q.x) / 6.2832);
    float3 c3 = mix(float3(0.45, 0.3, 0.18), float3(0.7, 0.55, 0.35), smoothstep(0.2, 0.8, spiral));
    c3 *= 0.7 + 0.4 * smoothstep(-0.6, 0.3, p.y);
    c3 += float3(1.0) * exp(-dot((p - float2(-0.2, 0.15)) / float2(0.18, 0.08), (p - float2(-0.2, 0.15)) / float2(0.18, 0.08))) * 0.35;
    return float4(c3 * a, a);
}
