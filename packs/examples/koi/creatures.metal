// A pond frog sitting (on a lily pad), facing +x: a squat body, a big eye on top, a folded hind leg that stretches
// out when it hops (extra.w), a throat that pulses, green with dark spots and a pale belly.
float4 draw_frog(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c + float2(0.0, 0.35);                                            // its feet at c.y = -0.9
    float hop = extra.w;
    float body = (length((p - float2(0.0, -0.05)) / float2(0.62, 0.42)) - 1.0) * 0.4;
    body = smin_k(body, (length((p - float2(0.42, 0.1)) / float2(0.32, 0.26)) - 1.0) * 0.26, 0.1);    // the head
    float eyeB = length(p - float2(0.46, 0.38)) - 0.13;
    float throat = (length((p - float2(0.5, -0.18)) / float2(0.2, 0.12 + 0.04 * max(0.0, sin(phase * 3.0)))) - 1.0) * 0.12;
    // hind leg: folded against the body, or stretched back in a hop
    float2 k0 = float2(-0.35, -0.2), k1 = mix(float2(-0.05, -0.55), float2(-0.8, -0.5), hop), k2 = mix(float2(-0.6, -0.6), float2(-1.0, -0.75), hop);
    float2 pa = p - k0, ba = k1 - k0;
    float thigh = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.13;
    pa = p - k1; ba = k2 - k1;
    float shin = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.07;
    float2 f0 = float2(0.35, -0.2), f1 = float2(0.5, -0.6);
    pa = p - f0; ba = f1 - f0;
    float arm = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.06;
    float d = min(min(min(body, eyeB), min(throat, thigh)), min(shin, arm));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 g = col.rgb;
    float3 c3 = g * (0.65 + 0.5 * smoothstep(-0.5, 0.4, p.y));
    float spots = smoothstep(0.62, 0.7, vnoise(p * 7.0 + extra.y * 10.0));
    c3 = mix(c3, g * 0.35, spots * 0.7 * step(-0.2, p.y));
    c3 = mix(c3, float3(0.9, 0.88, 0.7) * dot(g, float3(0.8)), smoothstep(-0.1, -0.3, p.y) * step(body, 0.0) * 0.7);   // belly
    if (throat < 0.0 && body > -0.02) c3 = float3(0.92, 0.9, 0.75) * dot(g, float3(0.9));
    c3 += float3(0.8, 1.0, 0.8) * (1.0 - smoothstep(0.0, 0.03, -d)) * smoothstep(0.0, 0.4, p.y) * 0.25;           // rim light
    // the eye: golden with a dark horizontal pupil
    float re = length(p - float2(0.48, 0.4));
    c3 = mix(c3, float3(0.85, 0.7, 0.25), 1.0 - smoothstep(0.08, 0.095, re));
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.85, 1.1, length((p - float2(0.49, 0.4)) / float2(0.06, 0.03))));
    c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.01, 0.02, length(p - float2(0.51, 0.44))));
    float mouth = abs(p.y + 0.02 + (p.x - 0.5) * 0.25) - 0.008;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.012, mouth)) * step(0.35, p.x) * step(p.x, 0.72) * 0.6;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    return float4(c3 * a * col.a, a * col.a);
}

// Tadpoles: a round dark head and a long tail that wiggles (phase), in a little school.
float4 draw_tadpole(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float head = (length((p - float2(0.4, 0.0)) / float2(0.38, 0.3)) - 1.0) * 0.3;
    float tx = clamp((0.1 - p.x) / 1.0, 0.0, 1.0);
    float ty = sin(phase * 3.0 - p.x * 6.0) * 0.18 * tx;
    float tail = max(abs(p.y - ty) - 0.13 * (1.0 - tx) - 0.02, max(p.x - 0.2, -p.x - 0.95));
    float fin = max(abs(p.y - ty) - 0.22 * (1.0 - tx) * smoothstep(0.0, 0.3, tx) - 0.015, max(p.x - 0.0, -p.x - 0.95));
    float d = min(head, tail);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float af = (1.0 - smoothstep(-aa, aa, fin)) * 0.35;
    float3 c3 = col.rgb * (0.6 + 0.5 * smoothstep(-0.3, 0.3, p.y));
    c3 += float3(0.9) * pow(max(0.0, 1.0 - length((p - float2(0.45, 0.13)) / float2(0.15, 0.07))), 2.0) * 0.4;   // a gleam
    c3 = mix(c3, float3(0.85, 0.75, 0.3), 1.0 - smoothstep(0.035, 0.05, length(p - float2(0.6, 0.06))));        // eye
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.018, 0.028, length(p - float2(0.61, 0.06))));
    float al = max(a, af);
    return float4(mix(col.rgb * 0.8, c3, a) * al * col.a, al * col.a);
}

// A freshwater shrimp walking on the sand, facing +x: a curved, see-through segmented body, long antennae, legs that
// step (phase) while it walks (extra.w), and a tail fan.
float4 draw_shrimp(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c + float2(0.0, 0.35);                                            // its feet at c.y = -0.9
    // the body: a curve of shrinking segments from the head (right) to the tail (left)
    float d = 1e3, seg = 0.0, segT = 0.0;
    float2 prev = float2(0.45, -0.05);
    for (int i = 1; i <= 7; i++) {
        float t = float(i) / 7.0;
        float2 q = float2(0.45 - t * 1.0, -0.05 + sin(t * 2.6) * 0.32 - t * 0.2);
        float2 pa = p - prev, ba = q - prev;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float r = mix(0.22, 0.09, t);
        float dd = length(pa - ba * h) - r;
        if (dd < d) { d = dd; seg = float(i); segT = h; }
        prev = q;
    }
    float head = (length((p - float2(0.45, -0.02)) / float2(0.3, 0.2)) - 1.0) * 0.2;
    float rostrum = sd_tri(p, float2(0.55, 0.08), float2(0.95, 0.12), float2(0.6, 0.0));
    float fan = sd_tri(p, prev + float2(0.05, 0.0), prev + float2(-0.3, 0.2), prev + float2(-0.3, -0.12)) - 0.01;
    // antennae and legs
    float lines = 1e3;
    for (int i = 0; i < 2; i++) {
        float2 a0 = float2(0.65, 0.05), a1 = float2(1.0, 0.45 + 0.15 * float(i) + sin(phase * 0.7 + float(i)) * 0.05);
        float2 pa = p - a0, ba = a1 - a0;
        lines = min(lines, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.01);
    }
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float step2 = sin(phase * 4.0 + fi * 1.6) * 0.06 * extra.w;
        float2 l0 = float2(0.38 - fi * 0.13, -0.12 - fi * 0.05), l1 = float2(0.44 - fi * 0.13 + step2, -0.55);
        float2 pa = p - l0, ba = l1 - l0;
        lines = min(lines, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.018);
    }
    float body = min(min(d, head), min(rostrum, fan));
    float all = min(body, lines);
    float aa = fwidth(all) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, all);
    // see-through: a pale glassy body with color along the back and the segment joints
    float3 c3 = mix(float3(0.9, 0.85, 0.8), col.rgb, 0.55) * (0.75 + 0.35 * smoothstep(-0.3, 0.3, p.y));
    c3 *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.12, abs(segT - 0.0))) * step(body, 0.0) * step(0.5, seg);
    c3 += float3(1.0) * (1.0 - smoothstep(0.0, 0.02, -body)) * 0.2;
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.03, 0.045, length(p - float2(0.55, 0.06))));          // eye
    float al = a * (body < 0.0 ? 0.85 : 0.7);
    return float4(c3 * al * col.a, al * col.a);
}
