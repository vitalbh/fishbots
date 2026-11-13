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

// A weather loach (dojo), facing +x: a long, soft, eel-like olive-brown fish with a paler belly, dark speckles, a
// small eye set high, barbels around a down-turned mouth and a rounded tail. While it moves (extra.w) it wriggles
// along the floor in a gentle S; while it rests it has buried itself: only the head and a hump of its back show
// above a little mound of sand. The mound is in the pond's sand colors (#3a3a34 … #7a786a), lit like col is: col is
// its pack.json color (#7a6a3c) lit by the hour, so the light is col against that color. p = c * (1.6, 0.6); the
// floor at p.y = -0.54.
float4 draw_koi_loach(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.6);
    float w = clamp(extra.w, 0.0, 1.0);
    float gy = -0.54;
    float R = 0.155;
    float light = clamp(dot(col.rgb, float3(0.333)) / 0.38, 0.0, 1.3);
    float x = p.x;
    // the line of its back: swimming, a low wave running tailward with the belly on the sand; buried, it dips
    // under the floor, with a hump of the back and the lifted head left out
    float wave = 0.5 + 0.5 * sin(phase * 1.5 - x * 4.2);
    float ySwim = gy + R + 0.015 + 0.11 * wave * smoothstep(1.15, 0.5, x) - 0.03 * smoothstep(0.85, 1.25, x);
    float breathe = sin(phase * 2.0) * 0.008;
    float yBury = gy - 0.2 + (0.47 + breathe) * exp(-pow((x + 0.35) / 0.44, 2.0)) + 0.37 * smoothstep(0.3, 0.8, x) - 0.03 * smoothstep(0.85, 1.25, x);
    float yc = mix(yBury, ySwim, w);
    // how thick it is along its length: a blunt head, an even body, a slimmer tail stock
    float prof = sqrt(max(0.0, 1.0 - pow(max(0.0, (x - 0.93) / 0.34), 2.0)));
    prof *= mix(0.6, 1.0, smoothstep(-1.2, -0.2, x)) * step(-1.22, x);
    float r = R * prof;
    float body = prof > 0.0 ? abs(p.y - yc) - r : 1.0;
    body *= 0.8;
    // the tail: a rounded paddle; the dorsal fin: a small soft lobe behind the middle; a pectoral fin low on the chest
    float yt = mix(gy - 0.2, gy + R + 0.015 + 0.11 * (0.5 + 0.5 * sin(phase * 1.5 + 1.22 * 4.2)), w);
    float tail = (length((p - float2(-1.28, yt)) / float2(0.2, 0.17)) - 1.0) * 0.17;
    float yd = mix(gy - 0.2, gy + 2.0 * R + 0.015 + 0.11 * (0.5 + 0.5 * sin(phase * 1.5 + 0.15 * 4.2)), w);
    float dors = max((length((p - float2(-0.15, yd - 0.03)) / float2(0.2, 0.13)) - 1.0) * 0.13, yd - 0.04 - p.y);
    float2 hq = float2(0.72, gy + 0.06);
    float pect = (length((p - hq - float2(-0.08, -0.02)) / float2(0.14, 0.05)) - 1.0) * 0.05;
    pect = mix(1.0, pect, w);
    float fins = min(min(tail, dors), pect);
    // the barbels: short whiskers around the mouth, feeling the sand
    float2 m = float2(1.22, gy + R - 0.05);
    float barb = 1e3;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 e = m + float2(0.1 - fi * 0.07, -0.1 - 0.02 * fi + sin(phase * 1.3 + fi * 2.0) * 0.012);
        e.y = max(e.y, gy + 0.01);
        barb = min(barb, sd_seg(p, m - float2(fi * 0.045, 0.0), e) - 0.016);
    }
    float d = min(min(body, fins), barb);
    float aa = fwidth(d) + 1e-4;
    // (outside its strip there's nothing; only after the edge is measured, or the cut shows as a thin line)
    if (p.y > gy + 0.62 || p.y < gy - 0.09) return float4(0.0);
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 olive = col.rgb;
    float3 c3;
    if (body <= min(fins, barb)) {
        float yn = clamp((p.y - yc) / max(r, 0.02), -1.0, 1.0);
        c3 = mix(olive, olive * float3(0.5, 0.52, 0.45), smoothstep(-0.3, 0.8, yn) * 0.7);                 // a darker back
        c3 = mix(c3, olive * 0.4 + float3(0.56, 0.52, 0.4) * light, smoothstep(-0.2, -0.85, yn) * 0.75);   // the pale belly
        // speckles, thicker along the back, and a faint dark line down the flank
        float2 sg = float2(x * 15.0, yn * 2.6) + extra.y * 7.0;
        float2 sid = floor(sg);
        float sp = step(0.5, hash21(sid)) * (1.0 - smoothstep(0.12, 0.3, length(fract(sg) - 0.5 - (float2(hash21(sid + 3.0), hash21(sid + 7.0)) - 0.5) * 0.5)));
        c3 = mix(c3, olive * 0.3, sp * 0.6 * smoothstep(-0.5, 0.1, yn));
        c3 = mix(c3, olive * 0.45, (1.0 - smoothstep(0.0, 0.14, abs(yn - 0.05))) * 0.3 * smoothstep(1.0, 0.6, x));
        c3 = fish_round(c3 * 1.12, float2(0.0, yn * 0.92), body);
        // the eye, small and high on the head, and the down-turned mouth
        float2 eye = float2(1.0, yc + 0.055);
        c3 = fish_eye(c3, p, eye, 0.05, float3(0.9, 0.7, 0.3), 0.0);
        float mouth = abs(p.y - (yc - 0.07 - (x - 1.1) * 0.5)) - 0.01;
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.012, mouth)) * step(1.1, x) * 0.45;
    } else if (barb < fins) {
        c3 = olive * 0.8 + float3(0.12, 0.1, 0.06) * light;
    } else {
        // the fins: thin, a little see-through, rayed, darker spots on the tail
        float2 tq = p - float2(-1.1, yt);
        float rays = 0.5 + 0.5 * cos(atan2(tq.y, -tq.x) * 22.0);
        c3 = (olive * 0.85 + float3(0.1, 0.09, 0.05) * light) * (0.82 + 0.18 * rays);
        c3 = mix(c3, olive * 0.4, smoothstep(0.55, 0.7, vnoise(p * 14.0)) * 0.4);
        a *= 0.82;
    }
    // nothing of it shows under the floor
    a *= smoothstep(gy - 0.005, gy + 0.015, p.y);
    float3 rgb = c3 * a;
    float al = a;
    // the mound it lies under, only while it rests: a low heap of sand, lumpy, lit from above, pressed around the
    // body where it goes in; it fades into the floor at its foot
    float bury = 1.0 - w;
    float mh = (0.3 * exp(-pow((x + 0.2) / 0.82, 4.0)) + 0.04 * exp(-pow((x - 0.1) / 1.2, 6.0)) + 0.04 * (vnoise(float2(x * 5.0 + extra.y * 9.0, 2.0)) - 0.5) * exp(-pow(x / 1.1, 4.0))) * bury;
    mh *= 1.0 - 0.22 * exp(-pow((x + 0.35) / 0.4, 2.0));                                 // it sags where the back comes out
    float md = p.y - (gy + mh);
    float ma = (1.0 - smoothstep(-0.012, 0.012, md)) * step(0.004, mh) * smoothstep(gy - 0.08, gy - 0.01, p.y);
    if (ma > 0.0) {
        float3 sDark = float3(0.227, 0.227, 0.204), sLight = float3(0.478, 0.471, 0.416);
        float up = clamp((p.y - gy) / max(mh, 0.02), 0.0, 1.0);
        float grain = vnoise(p * float2(26.0, 30.0) + extra.y * 3.0);
        float3 s3 = mix(sDark, sLight, 0.5 + 0.45 * up + 0.22 * (grain - 0.5));
        s3 += sLight * 0.3 * (1.0 - smoothstep(0.0, 0.035, -md));                          // light along its crest
        s3 += float3(0.07) * step(0.9, hash21(floor(p * 34.0)));                           // a few bright grains
        s3 *= light;
        // where the body comes out of it: a soft shadow on the sand
        s3 *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.07, body));
        rgb = mix(rgb, s3, ma);
        al = mix(al, 1.0, ma);
    }
    // its shadow on the floor while it swims
    float sh = (1.0 - smoothstep(0.0, 0.05, abs(p.y - gy + 0.015))) * (1.0 - smoothstep(1.0, 1.35, abs(x))) * 0.3 * w * (1.0 - al);
    al += sh;
    return float4(rgb * col.a, al * col.a);
}
