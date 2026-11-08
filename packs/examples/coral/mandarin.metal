// A mandarinfish, the reef's most colorful one (its music fish): blue with orange wavy lines, a big orange-edged
// dorsal fin, fan-like pectorals beating fast, and an orange tail.
float4 draw_coral_mandarin(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.0) * 0.04 * smoothstep(0.3, -0.8, p.x);
    float body = (length((p - float2(0.15, 0.0)) / float2(0.62, 0.27)) - 1.0) * 0.27;
    body = smin_k(body, (length((p - float2(0.6, 0.04)) / float2(0.22, 0.2)) - 1.0) * 0.2, 0.08);
    float dors = max((length((p - float2(-0.05, 0.3)) / float2(0.45, 0.2)) - 1.0) * 0.2, -(p.y - 0.18));
    float dors1 = sd_tri(p, float2(0.42, 0.2), float2(0.22, 0.22), float2(0.34, 0.5)) - 0.02;     // the tall first dorsal
    float anal = max((length((p - float2(-0.05, -0.25)) / float2(0.4, 0.12)) - 1.0) * 0.12, p.y + 0.15);
    float2 tq = p - float2(-0.5, sin(phase - 1.0) * 0.04);
    float tail = (length((tq - float2(-0.16, 0.0)) / float2(0.2, 0.22)) - 1.0) * 0.2;
    float beat = sin(phase * 7.0);                                                           // the pectorals whir
    float2 pq = p - float2(0.4, -0.1);
    float pang = -0.3 + beat * 0.6;
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.1, 0.0)) / float2(0.16, 0.1)) - 1.0) * 0.1;
    float fins = min(min(min(dors, dors1), anal), min(tail, pect));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = (1.0 - smoothstep(-aa, aa, d)) * col.a;
    if (a <= 0.0 && glow <= 0.0) return float4(0.0);
    float3 blue = float3(0.1, 0.35, 0.85), orange = float3(1.0, 0.5, 0.1), green = float3(0.2, 0.8, 0.5);
    // the pattern: blue ground, wavy orange bands edged in turquoise
    float w = sin(p.x * 16.0 + sin(p.y * 22.0 + p.x * 4.0) * 1.8 + vnoise(p * 6.0) * 2.0);
    float3 pat = mix(blue, orange, smoothstep(0.35, 0.6, w));
    pat = mix(pat, green, (1.0 - smoothstep(0.0, 0.15, abs(w - 0.3))) * 0.6);
    float3 c3;
    if (body <= fins) {
        float2 b = (p - float2(0.15, 0.0)) / float2(0.62, 0.27);
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 = pat * (0.6 + 0.55 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5)))));
        float2 eye = float2(0.66, 0.1);
        float re = length(p - eye);
        c3 = mix(c3, float3(0.9, 0.6, 0.1), 1.0 - smoothstep(0.05, 0.06, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.028, 0.036, re));
    } else {
        // fins: the pattern, darker, with orange rims; the pectorals clear and fast
        c3 = mix(pat * 0.8, orange, smoothstep(-0.03, -0.008, d) * 0.8);
        if (pect < min(min(dors, dors1), min(anal, tail))) { c3 = float3(0.85, 0.9, 1.0); a *= 0.45; }
        a *= 0.92;
    }
    c3 += col.rgb * glow * 0.3;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 10.0) * edge;
    return float4(c3 * a + orange * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
}
