// Koi: a long, heavy-shouldered carp with barbels, a long dorsal fin, big rounded pectoral fins and a flowing tail.
// Its variety comes from extra.y (the project's pattern): 0 kohaku (white with patches of `col`), 1 sanke (kohaku with
// small black spots), 2 ogon (all metallic `col`), 3 showa (black with patches of `col` and white). The patches are
// placed by the color itself, so each project's koi keeps its own.
float4 draw_koi(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int variety = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    float seed = fract(dot(col.rgb, float3(12.9898, 78.233, 37.719)) * 43.758);
    // the body swims in a wave, wider toward the tail
    p.y -= sin(phase - p.x * 2.2) * (0.012 + 0.08 * (1.0 - smoothstep(-1.0, 0.3, p.x)));

    // body: full at the shoulders, tapering into a long tail stock; a blunt, rounded head
    float cx = 0.08, rx = 0.84, ry = 0.23;
    float rear = smoothstep(cx + 0.2, cx - rx, p.x);
    float ryx = ry * (1.0 - 0.55 * rear) * (1.0 + 0.12 * smoothstep(0.1, 0.45, p.x) * step(0.0, p.y));
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    float body = (length(b) - 1.0) * min(rx, ryx);
    // tail: two soft lobes, long and flowing
    float bx = cx - rx * 0.92;
    float sw = sin(phase * 1.0 - 1.2) * 0.06;
    float2 tq = p - float2(bx, 0.0);
    tq.y -= sw * smoothstep(0.0, -0.45, tq.x);
    // a fan joined to the tail stock, its back edge rounded with a soft notch in the middle
    float tail = sd_tri(tq, float2(0.06, 0.0), float2(-0.5, 0.26), float2(-0.5, -0.26));
    tail = max(tail, length(tq - float2(0.06, 0.0)) - 0.6);
    tail = max(tail, -(length((tq - float2(-0.62, 0.0)) / float2(0.2, 0.1)) - 1.0) * 0.1);
    tail -= 0.015 + 0.01 * sin(tq.y * 20.0 + phase * 1.3) * smoothstep(-0.2, -0.5, tq.x);   // the soft edge flutters
    // a long dorsal fin along the back, pectoral fins like fans, a small pelvic and anal fin
    float dors = sd_tri(p, float2(cx + 0.3, ry * 0.85), float2(cx - 0.5, ry * 0.45), float2(cx - 0.4, ry + 0.07 + 0.012 * sin(phase * 1.3))) - 0.012;
    float pang = -0.65 + sin(phase * 0.9) * 0.25;
    float2 pq = p - float2(cx + rx * 0.42, -ry * 0.55);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.13, 0.0)) / float2(0.17, 0.08)) - 1.0) * 0.08;
    float pelv = sd_tri(p, float2(cx - 0.05, -ry * 0.75), float2(cx - 0.2, -ry * 0.7), float2(cx - 0.24, -ry - 0.1)) - 0.01;
    float anal = sd_tri(p, float2(cx - rx * 0.55, -ryx * 0.6), float2(cx - rx * 0.7, -ry * 0.35), float2(cx - rx * 0.74, -ry * 0.6 - 0.06)) - 0.008;
    float fins = min(min(dors, pelv), anal);
    // barbels: two whiskers at the corner of the mouth
    float barb = 1e3;
    for (int i = 0; i < 2; i++) {
        float2 a0 = float2(cx + rx * 0.93, -ry * 0.25), a1 = a0 + float2(0.05 + 0.03 * float(i), -0.07 - 0.03 * float(i) + sin(phase * 0.8 + float(i)) * 0.01);
        float2 pa = p - a0, ba = a1 - a0;
        barb = min(barb, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.006);
    }
    float d = min(min(min(body, tail), min(fins, pect)), barb);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    // colors: the skin's base and the patches
    float3 white = float3(0.96, 0.94, 0.9);
    float3 black = float3(0.08, 0.08, 0.1);
    float3 red = col.rgb;
    float2 np = p * float2(2.6, 3.4) + seed * 17.0;
    float patch = smoothstep(0.52, 0.58, vnoise(np) * 0.7 + vnoise(np * 2.3) * 0.3);
    float3 skin;
    if (variety == 2) {
        skin = mix(red, red * 1.25 + 0.15, vnoise(np * 1.5) * 0.4);                         // ogon: one metallic color
    } else if (variety == 3) {
        float wpatch = smoothstep(0.55, 0.6, vnoise(np * 1.3 + 9.0));
        skin = mix(mix(black, red, patch), white, wpatch * (1.0 - patch));              // showa
    } else {
        skin = mix(white, red, patch);                                                   // kohaku
        if (variety == 1) {                                                              // sanke: small black spots
            float2 sg = p * 7.0 + seed * 5.0;
            float2 sid = floor(sg);
            float sp = step(0.72, hash21(sid)) * (1.0 - smoothstep(0.15, 0.3, length(fract(sg) - 0.5 - (float2(hash21(sid + 1.0), hash21(sid + 2.0)) - 0.5) * 0.4)));
            skin = mix(skin, black, sp * step(0.0, p.y + ryx * 0.3));
        }
    }
    float yn = p.y / max(ryx, 0.02);
    float3 c3 = skin;
    if (body < 0.0) {
        // scales: a fine net, showing more on the metallic ones
        float2 sq = p * float2(16.0, 18.0); sq.x += fmod(floor(sq.y), 2.0) * 0.5;
        float sr = length(fract(sq) - float2(0.5, 0.0));
        float net = smoothstep(0.4, 0.47, sr) * (1.0 - smoothstep(0.5, 0.57, sr));
        c3 *= 1.0 - net * (variety == 2 ? 0.25 : 0.12);
        if (variety == 2) c3 += float3(1.0) * pow(max(0.0, sin(p.x * 30.0 + phase * 0.2) * sin(p.y * 40.0)), 12.0) * 0.4;
        // round shading: lit back, a soft belly, a sheen on the shoulders
        c3 *= 0.72 + 0.4 * smoothstep(-1.0, 0.8, yn);
        float2 hs = (p - float2(cx + 0.15, ryx * 0.45)) / float2(0.5, 0.12);
        c3 += float3(1.0) * pow(max(0.0, 1.0 - dot(hs, hs)), 2.0) * 0.18;
        float edge = 1.0 - smoothstep(0.0, 0.03, -body);
        c3 += float3(0.75, 0.9, 1.0) * edge * smoothstep(0.0, 0.8, yn) * 0.25;
        c3 *= 1.0 - edge * smoothstep(0.0, -0.8, yn) * 0.3;
        // the gill cover and the eye, low on the head
        float2 gc = float2(cx + rx * 0.62, -0.02);
        float garc = abs(length((p - gc) * float2(1.0, 0.8)) - 0.13);
        c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.014, garc)) * step(p.x, gc.x) * 0.25;
        float2 eye = float2(cx + rx * 0.8, ry * 0.08);
        float re = length(p - eye);
        if (asleep) c3 = mix(c3, black, (1.0 - smoothstep(0.0, 0.008, abs(p.y - eye.y + (p.x - eye.x) * (p.x - eye.x) * 8.0) - 0.004)) * step(re, 0.035));
        else {
            c3 = mix(c3, float3(0.85, 0.75, 0.45), 1.0 - smoothstep(0.03, 0.038, re));
            c3 = mix(c3, black, 1.0 - smoothstep(0.018, 0.025, re));
            c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.004, 0.008, length(p - eye - float2(0.006, 0.008))));
        }
    } else {
        // fins: thin and see-through, with rays, white at the edges (koi fins often are)
        float2 rr = p - float2(bx + 0.05, 0.0);
        float rays = 0.5 + 0.5 * cos(atan2(rr.y, -rr.x) * 26.0);
        float3 fin = mix(skin, white, 0.45) * (0.8 + 0.2 * rays);
        fin = mix(fin, white, smoothstep(-0.03, -0.005, d) * 0.5);
        c3 = barb < 0.0 && min(body, min(tail, fins)) > 0.0 ? skin * 0.85 : fin;
        if (pect < 0.0) c3 = mix(skin, white, 0.6) * (0.85 + 0.15 * cos(atan2(pq.y, pq.x + 0.25) * 20.0));
    }
    c3 += red * glow * 0.4;
    float finA = body < 0.0 ? 1.0 : 0.8;
    float a = inside * col.a * finA;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    return float4(c3 * a + red * halo * 0.9, min(a + halo * 0.55, 1.0));
}

// Medaka (rice fish): tiny and almost see-through, pale gold, a big eye set high with a blue-green shine over it, an
// upturned mouth, a long anal fin under the back half. The pond's schools. col tints it; extra.w > 1.5: asleep.
float4 draw_koi_medaka(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.8) * 0.045 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.34, 1.0, smoothstep(-0.9, 0.0, p.x));
    float ry = 0.2 * thin;
    float body = (length((p - float2(0.1, 0.0)) / float2(0.78, ry)) - 1.0) * ry;
    float2 tq = p - float2(-0.62, sin(phase - 1.2) * 0.04);
    float tail = max(sd_tri(tq, float2(0.08, 0.0), float2(-0.4, 0.3), float2(-0.4, -0.3)), length(tq - float2(0.06, 0.0)) - 0.38) - 0.01;   // a rounded fan
    float dors = sd_tri(p, float2(-0.3, 0.1), float2(-0.5, 0.06), float2(-0.48, 0.19)) - 0.01;            // small, far back
    float anal = sd_tri(p, float2(0.0, -0.16), float2(-0.52, -0.06), float2(-0.42, -0.25)) - 0.01;        // long
    float fins = min(tail, min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 gold = mix(float3(0.95, 0.8, 0.5), col.rgb, 0.35);
    float3 c3 = fish_round(gold, float2((p.x - 0.1) / 0.78, p.y / max(ry, 0.03)), body);
    float al = a;
    if (body > 0.0) { c3 = gold * 0.9 + 0.08; al *= 0.5; }
    else {
        // see-through: the silver gut shows low in the front half, the spine as a faint line
        c3 = mix(c3, float3(0.92, 0.95, 0.98), (1.0 - smoothstep(0.6, 1.0, length((p - float2(0.25, -0.05)) / float2(0.25, 0.09)))) * 0.55);
        c3 = mix(c3, gold * 0.6, (1.0 - smoothstep(0.0, 0.012, abs(p.y - 0.02))) * step(p.x, 0.3) * 0.35);
        c3 += float3(0.3, 0.9, 0.9) * (1.0 - smoothstep(0.5, 1.0, length((p - float2(0.6, 0.15)) / float2(0.12, 0.035)))) * 0.5;   // the shine over the eye
        al *= 0.88;
    }
    c3 = fish_eye(c3, p, float2(0.64, 0.07), 0.075, float3(0.75, 0.9, 0.95), extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}
