// A ryukin, the fancy goldfish: a round, high-backed body at the front and a long double tail that flows and folds
// behind it (the music fish of the pond). Its color follows the song a little (col) over the gold.
float4 draw_koi_ryukin(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    float body = (length((p - float2(0.42, 0.02)) / float2(0.36, 0.3)) - 1.0) * 0.3;
    body = smin_k(body, (length((p - float2(0.36, 0.22)) / float2(0.24, 0.14)) - 1.0) * 0.14, 0.08);   // the hump
    // the tail: two long veils from the tail stock, flowing and folding with the phase
    float tail = 1e3, tailT = 0.0;
    for (int k = -1; k <= 1; k += 2) {
        float fk = float(k);
        float2 q = p - float2(0.1, 0.0);
        float t = clamp(-q.x / 1.0, 0.0, 1.0);
        float y = fk * (0.03 + 0.14 * t) + sin(phase * 1.4 - t * 4.0 + fk * 0.6) * 0.12 * t;
        float w = 0.07 + 0.3 * t * (1.0 - 0.25 * t);
        float veil = max(abs(q.y - y) - w, max(q.x - 0.05, -q.x - 1.0 - 0.06 * sin(q.y * 9.0 + phase * 2.0)));
        if (veil < tail) { tail = veil; tailT = t; }
    }
    float dors = sd_tri(p, float2(0.48, 0.3), float2(0.22, 0.26), float2(0.24, 0.46 + 0.03 * sin(phase * 1.6))) - 0.02;
    float pect = (length((p - float2(0.5, -0.24 + 0.03 * sin(phase * 2.0))) / float2(0.14, 0.06)) - 1.0) * 0.06;
    float fins = min(min(tail, dors), pect);
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = (1.0 - smoothstep(-aa, aa, d)) * col.a;
    if (a <= 0.0 && glow <= 0.0) return float4(0.0);
    float3 gold = mix(float3(1.0, 0.55, 0.12), col.rgb, 0.25);
    float3 c3;
    if (body <= fins) {
        float2 b = (p - float2(0.42, 0.02)) / float2(0.36, 0.3);
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 = gold * (0.55 + 0.65 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5)))));
        c3 = mix(c3, float3(1.0, 0.9, 0.75), smoothstep(-0.05, -0.25, p.y) * 0.5);           // pale belly
        float2 sq = p * float2(18.0, 20.0); sq.x += fmod(floor(sq.y), 2.0) * 0.5;
        float sr = length(fract(sq) - float2(0.5, 0.0));
        c3 *= 1.0 - smoothstep(0.42, 0.48, sr) * (1.0 - smoothstep(0.5, 0.56, sr)) * 0.2;
        c3 += float3(1.0) * pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0, 0, 1))), 16.0) * 0.4;
        float2 eye = float2(0.66, 0.08);
        float re = length(p - eye);
        c3 = mix(c3, float3(0.95, 0.85, 0.6), 1.0 - smoothstep(0.045, 0.055, re));
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.025, 0.034, re));
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.006, 0.012, length(p - eye - float2(0.01, 0.012))));
    } else {
        // the veils: see-through, gold at the root fading to white at the edge, with fine rays
        float k = tail < min(dors, pect) ? tailT : 0.3;
        c3 = mix(gold, float3(1.0, 0.95, 0.85), smoothstep(0.2, 0.9, k));
        c3 *= 0.85 + 0.15 * cos(atan2(p.y, p.x - 0.1) * 40.0);
        a *= 0.85 - 0.35 * k;
    }
    c3 += gold * glow * 0.4;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 10.0) * edge;
    return float4(c3 * a + gold * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
}
