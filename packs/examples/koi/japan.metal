// Koinobori: a pole on the sand with carp streamers in the wind, the big one in the state's color (col, as the
// flag's cloth), a smaller one below; they ripple and flutter, more while busy. Feet at c.y ≈ -0.9.
float koi_streamer(float2 p, float2 at, float len, float w, float phase) {
    float2 q = p - at;
    float t = clamp(-q.x / len, 0.0, 1.0);                       // 0 at the mouth (the pole), 1 at the tail
    q.y -= sin(phase * 3.0 - t * 7.0) * 0.05 * t - t * t * 0.06;
    float r = w * (1.0 - 0.55 * t) * (1.0 + 0.15 * sin(t * 12.0 - phase * 4.0));
    float body = max(abs(q.y) - r, max(q.x, -q.x - len));
    float tail = sd_tri(q, float2(-len + 0.02, 0.0), float2(-len - 0.14, r * 1.4), float2(-len - 0.1, -r * 1.2));
    return min(body, tail);
}
float4 draw_koi_koinobori(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float busy = abs(extra.w - 1.0) < 0.5 ? 1.6 : 1.0;
    float pole = sd_box(p - float2(0.52, -0.02), float2(0.018, 0.9), 0.008);
    float ball = length(p - float2(0.52, 0.92)) - 0.04;
    float big = koi_streamer(p, float2(0.5, 0.6), 0.95, 0.19, phase * busy);
    float small = koi_streamer(p, float2(0.5, 0.12), 0.72, 0.14, phase * busy + 1.3);
    float d = min(min(pole, ball), min(big, small));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3;
    if (min(big, small) < min(pole, ball)) {
        bool isBig = big < small;
        float3 cloth = isBig ? col.rgb : float3(0.85, 0.25, 0.2);
        float2 q = p - (isBig ? float2(0.5, 0.6) : float2(0.5, 0.12));
        float len = isBig ? 0.95 : 0.72;
        float t = clamp(-q.x / len, 0.0, 1.0);
        // scales as arcs, a white eye ring at the mouth, folds light and shade
        float scales = smoothstep(0.35, 0.5, abs(fract(q.x * 9.0 + abs(q.y) * 6.0) - 0.5));
        c3 = cloth * (0.75 + 0.25 * scales) * (0.8 + 0.3 * sin(t * 7.0 - phase * 3.0 * busy));
        float2 eye = float2(-0.07, 0.02);
        float re = length(q - eye);
        c3 = mix(c3, float3(0.97), 1.0 - smoothstep(0.035, 0.045, re));
        c3 = mix(c3, float3(0.05), 1.0 - smoothstep(0.015, 0.024, re));
        c3 = mix(c3, float3(0.97), (1.0 - smoothstep(0.0, 0.012, abs(q.x + 0.02))) * 0.8);   // the mouth ring
    } else {
        c3 = ball < pole ? float3(0.85, 0.7, 0.35) : float3(0.55, 0.42, 0.3) * (0.8 + 0.3 * step(0.0, p.x - 0.52));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.25;
    c3 += col.rgb * glow * 0.3;
    return float4(c3 * a, a);
}

// Suisha: a wooden water wheel, paddles all around, turning — fast while busy, slowly otherwise. Its hub takes the
// state's color (col), like the helm's.
float4 draw_koi_suisha(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float busy = abs(extra.w - 1.0) < 0.5;
    float ang = phase * (busy > 0.5 ? 0.9 : 0.12);
    float2 q = float2(p.x * cos(ang) - p.y * sin(ang), p.x * sin(ang) + p.y * cos(ang));
    float r = length(q);
    float th = atan2(q.y, q.x);
    float rim = abs(r - 0.72) - 0.05;
    float inner = abs(r - 0.4) - 0.035;
    float spokes = max(abs(fract(th / 6.2832 * 8.0 + 0.5) - 0.5) * r * 6.2832 / 8.0 - 0.025, r - 0.72);
    float paddles = max(abs(fract(th / 6.2832 * 16.0 + 0.5) - 0.5) * r * 6.2832 / 16.0 - 0.03, max(0.72 - r, r - 0.95));
    float hub = r - 0.14;
    float d = min(min(min(rim, inner), min(spokes, paddles)), hub);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 wood = float3(0.5, 0.36, 0.22) * (0.8 + 0.3 * vnoise(q * 9.0));
    float3 c3 = wood * (0.7 + 0.4 * smoothstep(-0.9, 0.9, p.y));
    if (hub < 0.0) c3 = col.rgb * (0.8 + 0.4 * (1.0 - r / 0.14)) + col.rgb * glow * 0.5;
    // water dripping from the paddles on one side while it turns
    float drip = busy * (1.0 - smoothstep(0.0, 0.02, abs(p.x - 0.82 - 0.03 * sin(p.y * 20.0 + phase * 6.0)))) * step(p.y, -0.1) * step(-0.95, p.y);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.3;
    float wa = drip * 0.5;
    return float4(c3 * a + float3(0.7, 0.9, 1.0) * wa * (1.0 - a), a + wa * (1.0 - a) * 0.5);
}

// Namazu: the giant catfish of the old tales (it shakes the earth): long, flat-headed, dark and mottled, with a wide
// mouth and long whiskers. It trembles in error (state 5), like a quake.
float4 draw_koi_namazu(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.7);
    bool error = abs(extra.w - 5.0) < 0.5;
    if (error) p += float2(sin(phase * 40.0), cos(phase * 33.0)) * 0.012;
    p.y -= sin(phase * 1.6 - p.x * 2.0) * 0.06 * smoothstep(0.4, -1.4, p.x);
    float thin = mix(0.35, 1.0, smoothstep(-1.4, 0.3, p.x));
    float body = (length((p - float2(-0.05, -0.02)) / float2(1.35, 0.3 * thin)) - 1.0) * 0.3;
    float head = (length((p - float2(1.0, -0.04)) / float2(0.42, 0.24)) - 1.0) * 0.24;
    body = smin_k(body, head, 0.1);
    // a long low fin along the back to the tail, and the tail fin
    float fin = max(abs(p.y - 0.24 * thin - 0.02) - 0.05 * thin, max(p.x - 0.1, -p.x - 1.35));
    float2 tq = p - float2(-1.3, sin(phase * 1.6) * 0.06);
    float tail = sd_tri(tq, float2(0.05, 0.0), float2(-0.22, 0.2), float2(-0.22, -0.2)) - 0.02;
    tail = max(tail, length(tq) - 0.24);
    body = smin_k(body, tail, 0.05);
    // whiskers: two long ones from the upper lip, swaying
    float wh = 1e3;
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float2 a0 = float2(1.32, 0.02 - fk * 0.08);
        for (int j = 0; j < 4; j++) {
            float t1 = float(j + 1) / 4.0;
            float2 a1 = a0 + float2(0.12 - 0.02 * t1, -0.06 - 0.05 * t1 + sin(phase * 1.2 + fk + t1 * 3.0) * 0.03);
            float2 pa = p - a0, ba = a1 - a0;
            wh = min(wh, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - mix(0.014, 0.005, t1));
            a0 = a1;
        }
    }
    float d = min(min(body, fin), wh);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 dark = col.rgb * 0.45, pale = mix(col.rgb, float3(0.8, 0.75, 0.6), 0.5);
    float yn = p.y / max(0.3 * thin, 0.05);
    float3 c3 = mix(pale, dark, smoothstep(-0.4, 0.2, yn));                      // dark back, pale belly
    c3 = mix(c3, dark * 0.6, smoothstep(0.55, 0.7, vnoise(p * float2(5.0, 9.0))) * step(-0.1, yn) * 0.7);   // mottles
    c3 *= 0.75 + 0.35 * smoothstep(-1.0, 0.8, yn);
    c3 += float3(0.7, 0.85, 0.9) * (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.2, 0.9, yn) * 0.2;
    // the wide mouth and the small eye
    float mouth = abs(p.y + 0.06 + (p.x - 1.4) * 0.15) - 0.008;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.012, mouth)) * step(1.0, p.x) * 0.6;
    float re = length(p - float2(1.18, 0.06));
    c3 = mix(c3, float3(0.85, 0.75, 0.4), 1.0 - smoothstep(0.03, 0.04, re));
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.015, 0.022, re));
    if (fin < body) c3 = mix(dark, pale, 0.25) * 0.9;
    if (wh < min(body, fin)) c3 = dark * 1.2;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;
    c3 += col.rgb * glow * 0.35;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 10.0) * edge;
    return float4(c3 * a + col.rgb * halo * (1.0 - a), a + halo * (1.0 - a) * 0.5);
}
