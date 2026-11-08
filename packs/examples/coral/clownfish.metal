// A clownfish: a short, round orange body with three white bands edged in black, rounded fins with black rims and a
// fan tail. Three varieties by the project's pattern (extra.y): 0 orange (ocellaris), 1 black (the dark form, with an
// orange face), 2 maroon. col is ignored: a clownfish is a clownfish.
float4 draw_clownfish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int variety = int(extra.y + 0.5) % 3;
    bool asleep = extra.w > 1.5;
    p.y -= sin(phase - p.x * 2.4) * (0.012 + 0.06 * (1.0 - smoothstep(-0.9, 0.3, p.x)));
    // body: round and short, a blunt head
    float cx = 0.12, rx = 0.62, ry = 0.34;
    float rear = smoothstep(cx + 0.2, cx - rx, p.x);
    float ryx = ry * (1.0 - 0.38 * rear);
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    float body = (length(b) - 1.0) * min(rx, ryx);
    float bx = cx - rx * 0.88;
    // tail: a rounded fan; fins: a long soft dorsal in two parts, a round anal fin, a paddle pectoral
    float2 tq = p - float2(bx, sin(phase - 1.0) * 0.04);
    float tail = (length((tq - float2(-0.13, 0.0)) / float2(0.2, 0.24)) - 1.0) * 0.2;
    tail = max(tail, tq.x - 0.02);
    tail = smin_k(tail, (length(tq / float2(0.12, 0.08)) - 1.0) * 0.08, 0.06);      // joined to the tail stock
    float dors = (length((p - float2(cx - 0.12, ry * 0.85)) / float2(0.42, 0.16)) - 1.0) * 0.16;
    dors = max(dors, -(p.y - ry * 0.55));
    dors = max(dors, -(length(p - float2(cx + 0.05, ry + 0.12)) - 0.07));         // the notch between spiny and soft
    float anal = (length((p - float2(cx - 0.3, -ryx * 0.9)) / float2(0.2, 0.14)) - 1.0) * 0.14;
    anal = max(anal, p.y + ryx * 0.5);
    float pang = -0.5 + sin(phase * 1.8) * 0.4;
    float2 pq = p - float2(cx + rx * 0.3, -ry * 0.2);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.1, 0.0)) / float2(0.13, 0.07)) - 1.0) * 0.07;
    float fins = min(min(tail, dors), anal);
    float d = min(min(body, fins), pect);
    float aa = fwidth(d) + 1e-4;
    float a = (1.0 - smoothstep(-aa, aa, d)) * col.a;
    if (a <= 0.0 && glow <= 0.0) return float4(0.0);

    float3 orange = float3(1.0, 0.45, 0.08);
    float3 skin = variety == 1 ? float3(0.07, 0.06, 0.07) : variety == 2 ? float3(0.5, 0.08, 0.1) : orange;
    float3 white = float3(0.97, 0.96, 0.94), black = float3(0.04, 0.03, 0.04);
    float yn = p.y / max(ryx, 0.02);
    float3 c3;
    if (body <= min(fins, pect) || (pect < 0.0 && body < 0.0)) {
        // three bands, curved like the real ones: behind the eye, in the middle (with a bump forward), at the tail
        float x = p.x - 0.04 * sin(p.y * 6.0);
        float b1 = abs(x - (cx + rx * 0.5)) - 0.07;
        float b2 = abs(x - (cx - 0.08) - 0.08 * exp(-p.y * p.y * 20.0)) - 0.08;
        float b3 = abs(x - (bx + 0.06)) - 0.045;
        float band = min(min(b1, b2), b3);
        c3 = skin;
        if (variety == 1) c3 = mix(c3, orange, smoothstep(cx + rx * 0.62, cx + rx * 0.82, p.x));   // the dark form's orange face
        c3 = mix(c3, black, 1.0 - smoothstep(0.012, 0.03, band));
        c3 = mix(c3, white, 1.0 - smoothstep(-0.008, 0.008, band));
        // round, lit from above: a sheen on the shoulders, darker belly line
        float3 n = normalize(float3(b, sqrt(max(0.02, 1.0 - dot(b, b)))));
        c3 *= 0.55 + 0.6 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5))));
        c3 += float3(1.0) * pow(max(0.0, dot(reflect(-normalize(float3(-0.3, 0.8, 0.5)), n), float3(0, 0, 1))), 18.0) * 0.3;
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.0, -0.8, yn) * 0.35;
        // eye
        float2 eye = float2(cx + rx * 0.72, ry * 0.18);
        float re = length(p - eye);
        if (asleep) c3 = mix(c3, black, (1.0 - smoothstep(0.0, 0.01, abs(p.y - eye.y) - 0.006)) * step(re, 0.06));
        else {
            c3 = mix(c3, float3(0.9, 0.55, 0.15), 1.0 - smoothstep(0.05, 0.062, re));
            c3 = mix(c3, black, 1.0 - smoothstep(0.03, 0.04, re));
            c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.006, 0.013, length(p - eye - float2(0.012, 0.016))));
        }
        if (pect < 0.0) c3 = mix(c3, skin * 1.1 + 0.05, 0.5);
    } else {
        // fins: the body's color, a black rim, a thin white edge inside it, a little see-through
        float rim = smoothstep(-0.035, -0.012, d);
        c3 = mix(skin * 0.95, black, rim);
        c3 = mix(c3, white, (1.0 - smoothstep(0.004, 0.012, abs(d + 0.042))) * 0.6);
        float2 rr = p - float2(bx + 0.05, 0.0);
        c3 *= 0.88 + 0.12 * cos(atan2(rr.y, -rr.x) * 24.0);
        a *= 0.92;
    }
    c3 += orange * glow * 0.4;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge;
    return float4(c3 * a + orange * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
}

// The clownfish that live in the anemones (a creature with "behavior": "home"): the pack's clownfish drawing, the
// orange kind, its tail going as it swims about.
float4 draw_coral_clown_home(float2 c, float phase, float glow, float4 col, float4 extra) {
    return draw_clownfish(c, phase, 0.0, float4(1.0), float4(1.0, extra.y < 0.85 ? 0.0 : 1.0, 0.0, 0.2));
}
