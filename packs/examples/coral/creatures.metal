// Blue-green chromis: tiny, deep-bodied, forked tail, in a school. col is their color.
float4 draw_coral_chromis(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 1.0);
    p.y -= sin(phase * 2.0 - p.x * 3.0) * 0.05 * smoothstep(0.3, -0.9, p.x);
    float body = (length((p - float2(0.15, 0.0)) / float2(0.75, 0.42)) - 1.0) * 0.42;
    float tail = sd_tri(p, float2(-0.5, 0.0), float2(-1.05, 0.38), float2(-1.05, -0.38));
    tail = max(tail, -sd_tri(p, float2(-0.8, 0.0), float2(-1.1, 0.22), float2(-1.1, -0.22)));
    // a spiny dorsal fin along the back and a small anal fin
    float dors = max((length((p - float2(0.05, 0.3)) / float2(0.5, 0.24)) - 1.0) * 0.24, 0.3 - p.y);
    float anal = max((length((p - float2(-0.15, -0.3)) / float2(0.3, 0.2)) - 1.0) * 0.2, p.y + 0.3);
    float fins = min(tail - 0.01, min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = fish_round(col.rgb, (p - float2(0.15, 0.0)) / float2(0.75, 0.42), body);
    if (body > 0.0) {
        c3 = col.rgb * 0.72 * (0.88 + 0.12 * cos(atan2(p.y, -(p.x + 0.3)) * 26.0));     // fins: darker, with rays
        a *= 0.85;
    }
    c3 = fish_eye(c3, p, float2(0.62, 0.08), 0.095, col.rgb, step(1.5, extra.w));     // asleep: a session wearing it
    return float4(c3 * a * col.a, a * col.a);
}

// A blue tang crossing the reef now and then: an oval blue body with the black "palette" mark and a yellow tail.
float4 draw_coral_tang(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.4, 1.0);
    p.y -= sin(phase - p.x * 2.4) * 0.05 * smoothstep(0.3, -1.0, p.x);
    float body = (length((p - float2(0.1, 0.0)) / float2(0.78, 0.5)) - 1.0) * 0.5;
    float dors = max((length((p - float2(0.0, 0.32)) / float2(0.7, 0.2)) - 1.0) * 0.2, -(p.y - 0.3));
    float anal = max((length((p - float2(-0.1, -0.3)) / float2(0.55, 0.16)) - 1.0) * 0.16, p.y + 0.28);
    float2 tq = p - float2(-0.68, sin(phase - 1.0) * 0.04);
    float tail = max(sd_tri(tq, float2(0.05, 0.0), float2(-0.38, 0.34), float2(-0.38, -0.34)),
                     -(length((tq - float2(-0.5, 0.0)) / float2(0.2, 0.2)) - 1.0) * 0.2) - 0.01;
    float d = min(min(body, tail), min(dors, anal));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 blue = float3(0.15, 0.35, 0.95), black = float3(0.03, 0.04, 0.08), yellow = float3(1.0, 0.82, 0.15);
    float3 c3 = blue;
    // the "palette": a thick black band from behind the eye along the back, curving down to the tail, with a
    // blue window in its middle
    float yb = 0.2 - 0.45 * (p.x - 0.35) * (p.x - 0.35);
    float band = abs(p.y - yb) - mix(0.04, 0.11, smoothstep(0.45, -0.1, p.x));
    float window = length((p - float2(-0.12, 0.13)) / float2(0.22, 0.05)) - 1.0;
    float mark = max(band, -window * 0.05) ;
    c3 = mix(c3, black, (1.0 - smoothstep(0.0, 0.012, mark)) * step(body, 0.0) * step(-0.62, p.x) * step(p.x, 0.5));
    if (tail < min(body, min(dors, anal))) c3 = yellow * (0.85 + 0.15 * cos(atan2(tq.y, -tq.x) * 20.0));
    if (min(dors, anal) < min(body, tail)) c3 = mix(blue * 0.8, black, smoothstep(-0.03, -0.005, min(dors, anal)));
    if (body < min(tail, min(dors, anal))) c3 = fish_round(c3 * 1.15, (p - float2(0.1, 0.0)) / float2(0.78, 0.5), body);
    else c3 *= 0.75 + 0.35 * smoothstep(-0.5, 0.5, p.y);
    c3 = fish_eye(c3, p, float2(0.62, 0.12), 0.06, float3(0.9, 0.8, 0.3), 0.0);
    return float4(c3 * a * col.a, a * col.a);
}


// A masked butterflyfish: a tall disc of a body, flat as a coin, with a small snout stuck out under a dished
// forehead; the dorsal fin starts as a comb of spines and swells into a soft lobe that squares the body off behind,
// the anal fin mirrors it below, and a short stock carries a clear fan of a tail. Golden yellow, thin orange bars
// following the curve of the flank, a blue-gray mask over the eye and cheek, a dark line just inside the edge of the
// soft fins. They go in pairs around the corals. col is the light of the hour.
float4 draw_coral_butterfly(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.1, 1.0);
    float moving = clamp(extra.w, 0.0, 1.0);
    // the whole fish yaws a little as it sculls; the tail end swings more
    p.y -= sin(phase * 1.6 - p.x * 2.2) * (0.012 + 0.03 * moving) * smoothstep(0.25, -0.8, p.x);
    float2 bc = float2(0.06, 0.0), br = float2(0.5, 0.5);
    float2 b = (p - bc) / br;
    float body = (length(b) - 1.0) * 0.5;
    // the snout: a short cone low on the face, the forehead dished above it
    float snout = sd_tri(p, float2(0.4, 0.1), float2(0.38, -0.2), float2(0.72, -0.075)) - 0.045;
    body = smin_k(body, snout, 0.07);
    body = max(body, -((length(p - float2(0.76, 0.2)) - 0.2)));
    // the fins along the back and the belly: one tall rounded plate behind the body's middle, cut off at the tail stock
    float2 fq = (p - float2(-0.1, 0.0)) / float2(0.5, 0.68);
    float plate = (length(float2(fq.x, fq.y * (0.86 + 0.14 * fq.x))) - 1.0) * 0.5;
    plate = max(plate, p.x - 0.3);
    plate = max(plate, -(p.x + 0.52) - 0.0 + 0.0 * p.y);                               // squared off behind
    plate = max(plate, 0.07 - abs(p.y) - (p.x + 0.52) * 0.9);                          // and nipped in at the stock
    // the comb of spines at the front of the dorsal
    float spines = 0.022 * abs(sin(p.x * 34.0)) * smoothstep(-0.2, 0.0, p.x) * step(0.0, p.y);
    float fins = plate - spines * 0.0 + (1.0 - abs(sin(p.x * 34.0))) * 0.03 * smoothstep(-0.18, 0.05, p.x) * step(0.0, p.y);
    // the tail: a stock and a fan, swinging
    float2 tq = p - float2(-0.5, sin(phase * 1.6 - 1.2) * (0.015 + 0.03 * moving));
    float stock = sd_box(tq - float2(-0.02, 0.0), float2(0.06, 0.085), 0.03);
    float fan = max(sd_tri(tq, float2(0.0, 0.0), float2(-0.42, 0.34), float2(-0.42, -0.34)), length(tq) - 0.36) - 0.012;
    float tail = min(stock, fan);
    // the pelvic fin under the chest and the pectoral fanning on the flank
    float pelv = sd_tri(p, float2(0.24, -0.4), float2(0.06, -0.44), float2(0.08, -0.7)) - 0.02;
    float d = min(min(body, fins), min(tail, pelv));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a < 0.002) return float4(0.0);
    float3 yellow = float3(1.0, 0.8, 0.14), deep = float3(0.96, 0.55, 0.08), orange = float3(0.92, 0.36, 0.1);
    float3 mask = float3(0.3, 0.4, 0.56), dark = float3(0.16, 0.12, 0.1);
    float3 c3;
    if (body <= 0.0) {
        // the flank: warmer toward the back, bars that bow with the body
        c3 = mix(yellow, deep, smoothstep(0.1, -0.9, b.x) * 0.45);
        float bx = (p.x + 0.07 * b.y * b.y) * 8.5;
        float bar = abs(fract(bx) - 0.5);
        float bw = fwidth(bx);
        c3 = mix(c3, orange, (1.0 - smoothstep(0.1 - bw, 0.1 + bw, bar)) * smoothstep(0.34, 0.2, p.x) * 0.8);
        // the mask: over the eye and down the cheek
        float2 eye = float2(0.4, 0.09);
        float2 mq = p - float2(0.37, 0.02);
        float m = (length(mq / float2(0.085, 0.2)) - 1.0) * 0.085;
        c3 = mix(c3, mask, 1.0 - smoothstep(-0.012, 0.012, m));
        c3 = mix(c3, float3(1.0, 0.92, 0.6), (1.0 - smoothstep(0.0, 0.03, abs(m - 0.02))) * 0.35);   // a pale rim to it
        c3 = fish_round(c3, b * 0.78, d);                                                            // flat as a coin
        c3 = mix(c3, c3 * 0.7, smoothstep(0.58, 0.74, p.x));                                         // the lips
        c3 = fish_eye(c3, p, eye, 0.062, float3(0.95, 0.8, 0.3), 0.0);
        // the pectoral fin: a clear little fan on the flank, beating
        float2 pq = p - float2(0.2, -0.1);
        float pa = atan2(pq.y, -pq.x) + 0.35 + sin(phase * 3.2) * 0.25 * (0.4 + 0.6 * moving);
        float pf = max(length(pq) - 0.2, abs(pa) - 0.55);
        float pfa = (1.0 - smoothstep(-0.01, 0.01, pf)) * 0.55;
        c3 = mix(c3, float3(1.0, 0.95, 0.7) * (0.85 + 0.15 * cos(pa * 22.0)), pfa);
    } else if (fins > 0.0 && tail < pelv) {
        // the tail: yellow at the stock, clear toward the edge, rayed
        float r = length(tq) / 0.36;
        c3 = mix(yellow * 0.95, float3(1.0, 0.92, 0.55), smoothstep(0.35, 1.0, r)) * (0.88 + 0.12 * cos(atan2(tq.y, -tq.x) * 26.0));
        c3 = mix(c3, orange, (1.0 - smoothstep(0.0, 0.03, abs(r - 0.45))) * 0.6 * step(stock, 0.0) * 0.0 + (1.0 - smoothstep(0.02, 0.05, abs(r - 0.5))) * 0.45);
        a *= mix(0.95, 0.72, smoothstep(0.5, 1.0, r));
    } else if (fins > 0.0) {
        c3 = yellow * (0.8 + 0.2 * smoothstep(-0.75, -0.45, p.y));
        a *= 0.9;
    } else {
        // the soft fins: the body's yellow, lit from above, rays fanning from the body, a dark line inside a bright edge
        float up = smoothstep(-0.6, 0.6, p.y);
        c3 = mix(yellow, deep, 0.2) * (0.8 + 0.36 * up);
        c3 *= 0.94 + 0.06 * cos(atan2(p.y, p.x + 0.1) * 60.0);
        float rear = smoothstep(0.05, -0.2, p.x);
        c3 = mix(c3, dark, (1.0 - smoothstep(0.012, 0.03, abs(plate + 0.05))) * 0.75 * rear);
        c3 = mix(c3, float3(1.0, 0.93, 0.5), (1.0 - smoothstep(0.0, 0.03, -plate)) * 0.6 * rear);
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.04, body)) * 0.12;                                      // the body's shade on them
        a *= 0.93;
    }
    c3 *= col.rgb;
    return float4(c3 * a * col.a, a * col.a);
}

// The chromis as a fish kind (a fish's quad is 1.25 × 0.8): the reef's schools, and a session can be one.
float4 draw_coral_chromis_fish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float4 o = draw_coral_chromis(c * float2(1.25 / 1.6, 0.8), phase, glow, col, extra);
    return float4(o.rgb + col.rgb * glow * 0.45 * o.a, o.a);
}

// A parrotfish, the reef's gardener: a stout turquoise body in big pink-edged scales, a blunt head ending in a pale
// beak, pink bands across the face, a low fin all along the back, a crescent tail edged in blue. It rows with its
// pectoral fins, and where it stops it bobs at the coral, biting, and lets fall a little cloud of chewed sand.
// col is the light of the hour; extra.w 1 while it swims, 0 while it nibbles.
float4 draw_coral_parrotfish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.4, 0.8);
    float moving = clamp(extra.w, 0.0, 1.0);
    float2 p0 = p;
    // nibbling: quick little lunges of the whole fish, nose down
    float bite = (1.0 - moving) * max(0.0, sin(phase * 2.6));
    p -= float2(0.035, -0.02) * bite;
    p.y -= sin(phase * 0.9 - p.x * 2.0) * (0.01 + 0.025 * moving) * smoothstep(0.2, -1.1, p.x);
    float2 bc = float2(-0.02, 0.0), br = float2(0.84, 0.4);
    float2 b = (p - bc) / br;
    // the body tapers to the tail stock; the head is blunt and high-browed
    float taper = mix(0.42, 1.0, smoothstep(-1.0, -0.1, b.x));
    float body = (length(float2(b.x, b.y / taper)) - 1.0) * 0.4;
    float head = length((p - float2(0.5, 0.01)) / float2(0.38, 0.38)) - 1.0;
    body = smin_k(body, head * 0.37, 0.1);
    // the beak: fused teeth, a pale bulge at the tip of the snout, parted by the mouth
    float2 kq = p - float2(0.865, -0.055);
    float beak = length(kq / float2(0.075, 0.1)) - 1.0;
    body = smin_k(body, beak * 0.075, 0.05);
    // the long low fin on the back, the one under the tail end
    float dors = max((length((p - float2(-0.12, 0.3)) / float2(0.62, 0.2)) - 1.0) * 0.2, 0.26 - p.y + 0.12 * (p.x + 0.1) * (p.x + 0.1));
    float anal = max((length((p - float2(-0.42, -0.28)) / float2(0.3, 0.16)) - 1.0) * 0.16, p.y + 0.24);
    // the tail: a crescent, its tips trailing
    float2 tq = p - float2(-0.84, sin(phase * 0.9 - 1.3) * (0.01 + 0.03 * moving));
    float fan = max(sd_tri(tq, float2(0.1, 0.0), float2(-0.5, 0.56), float2(-0.5, -0.56)), length(tq) - 0.5);
    fan = max(fan, -(length(tq - float2(-0.74, 0.0)) - 0.4)) - 0.012;
    float fins = min(dors, anal);
    float d = min(min(body, fan), fins);
    // the crumbs: a few specks of chewed coral drifting down from the beak while it bites
    float crumbs = 0.0;
    if (moving < 0.5) {
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float life = fract(phase * 0.16 + fi * 0.21);
            float2 at = float2(0.98 + 0.08 * hash21(float2(fi, 3.0)) + 0.06 * life, -0.12 - 0.5 * life * life - 0.05 * fi * 0.2)
                      + float2(sin(life * 9.0 + fi) * 0.03, 0.0);
            float r = mix(0.03, 0.065, life);
            crumbs += (1.0 - smoothstep(r * 0.4, r, length(p0 - at))) * (1.0 - life) * smoothstep(0.0, 0.1, life) * 0.75;
        }
    }
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a < 0.002 && crumbs < 0.002) return float4(0.0);
    float3 teal = float3(0.1, 0.74, 0.7), green = float3(0.35, 0.82, 0.45), pink = float3(0.98, 0.5, 0.62);
    float3 blue = float3(0.16, 0.45, 0.95), cream = float3(0.95, 0.92, 0.8);
    float3 c3;
    if (body <= 0.0) {
        // teal on the back running to green and a wash of yellow on the belly
        c3 = mix(green, teal, smoothstep(-0.5, 0.4, b.y));
        c3 = mix(c3, float3(0.95, 0.85, 0.4), smoothstep(-0.2, -1.0, b.y) * 0.35);
        // big scales: staggered rows, each edged in pink
        float2 sg = float2(p.x * 7.5, p.y * 8.5);
        sg.x += 0.5 * floor(sg.y);
        float2 sf = fract(sg) - float2(0.5, 0.5);
        float sc = length(sf - float2(0.32, 0.0));
        float rim = smoothstep(0.52, 0.66, sc) * (1.0 - smoothstep(0.7, 0.82, sc));
        float onflank = smoothstep(0.42, 0.25, p.x) * smoothstep(-0.95, -0.7, p.x);
        c3 = mix(c3, pink, rim * 0.55 * onflank);
        c3 *= 1.0 + 0.1 * (1.0 - smoothstep(0.1, 0.5, sc)) * onflank;
        // the face: pink bands from the eye to the mouth and over the cheek, a pink chin
        float2 eye = float2(0.6, 0.12);
        float band1 = abs((p.y - 0.06) - (p.x - 0.6) * -0.45) - 0.022;
        float band2 = abs((p.y + 0.1) - (p.x - 0.55) * 0.12) - 0.02;
        float face = smoothstep(0.36, 0.5, p.x) * (1.0 - smoothstep(0.8, 0.86, p.x));
        c3 = mix(c3, pink, (1.0 - smoothstep(0.0, 0.015, min(band1, band2))) * face * 0.85);
        c3 = mix(c3, pink * 1.02, smoothstep(-0.16, -0.3, p.y) * smoothstep(0.35, 0.6, p.x) * 0.6);
        c3 = fish_round(c3, b * float2(0.92, 0.85), d);
        // the beak, with the line of the mouth
        float kb = 1.0 - smoothstep(-0.3, 0.1, beak + 0.9 * smoothstep(0.02, -0.07, kq.x));
        c3 = mix(c3, mix(cream, teal, 0.12) * (0.8 + 0.25 * smoothstep(-0.1, 0.08, kq.y)), kb);
        c3 = mix(c3, float3(0.3, 0.2, 0.2), (1.0 - smoothstep(0.004, 0.012, abs(kq.y + 0.005 + 0.012 * bite))) * kb * step(-0.02, kq.x) * 0.8);
        c3 = fish_eye(c3, p, eye, 0.06, float3(1.0, 0.75, 0.3), 0.0);
        // the pectoral fin: a clear pink fan, rowing
        float2 pq = p - float2(0.3, -0.06);
        float row = sin(phase * (0.9 + 0.9 * moving)) * (0.25 + 0.3 * moving);
        float pa = atan2(pq.y, -pq.x) + 0.3 + row;
        float pf = max(length(pq / float2(1.0, 0.9)) - 0.27, abs(pa) - 0.5);
        c3 = mix(c3, mix(pink, cream, 0.35) * (0.85 + 0.15 * cos(pa * 24.0)), (1.0 - smoothstep(-0.012, 0.012, pf)) * 0.62);
    } else if (fan < fins) {
        // the tail: teal at the stock, a pink band, blue along both edges
        float r = length(tq) / 0.5;
        c3 = mix(teal * 0.9, pink, smoothstep(0.3, 0.6, r) * (1.0 - smoothstep(0.6, 0.85, r)) * 0.8);
        c3 *= 0.88 + 0.12 * cos(atan2(tq.y, -tq.x) * 22.0);
        c3 = mix(c3, blue, smoothstep(0.55, 0.95, abs(tq.y) / max(0.05, -tq.x)) * 0.85);
        c3 = mix(c3, blue, 1.0 - smoothstep(0.0, 0.04, -fan));
        a *= 0.92;
    } else {
        // the fins: pink, edged in blue
        c3 = pink * (0.8 + 0.25 * smoothstep(-0.4, 0.4, p.y)) * (0.92 + 0.08 * cos(p.x * 60.0 + p.y * 14.0));
        c3 = mix(c3, blue, 1.0 - smoothstep(0.0, 0.035, -fins));
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.05, body)) * 0.2;
        a *= 0.9;
    }
    c3 *= col.rgb;
    float3 sand = float3(0.95, 0.9, 0.78) * col.rgb;
    float ca = crumbs * (1.0 - a);
    return float4((c3 * a + sand * ca) * col.a, (a + ca) * col.a);
}

// A lyretail anthias, the reef's cloud of little pink-orange fish: a slim oval body, a tall spine at the front of
// the dorsal fin, a deeply forked tail with trailing tips, a violet streak from the eye to the fin on its flank.
// A fish kind (quad 1.25 × 0.8): col is the school's or the project's color.
float4 draw_coral_anthias(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase * 2.0 - p.x * 3.0) * 0.045 * smoothstep(0.3, -1.0, p.x);
    float2 bc = float2(0.22, 0.0), br = float2(0.62, 0.29);
    float2 b = (p - bc) / br;
    float taper = mix(0.35, 1.0, smoothstep(-1.0, 0.0, b.x));
    float body = (length(float2(b.x, b.y / taper)) - 1.0) * 0.29;
    // the lyre tail: two long lobes, the notch deep between them
    float2 tq = p - float2(-0.36, 0.0);
    float lobes = min(sd_seg(tq, float2(0.0, 0.03), float2(-0.72, 0.4)) - mix(0.075, 0.012, smoothstep(0.0, -0.72, tq.x)),
                      sd_seg(tq, float2(0.0, -0.03), float2(-0.72, -0.4)) - mix(0.075, 0.012, smoothstep(0.0, -0.72, tq.x)));
    float web = max(sd_tri(tq, float2(0.04, 0.0), float2(-0.34, 0.2), float2(-0.34, -0.2)), -(length(tq - float2(-0.42, 0.0)) - 0.2));
    float tail = min(lobes, web);
    // the dorsal: low along the back, its third spine a tall streamer; the anal and pelvic fins pointed
    float dors = max((length((p - float2(0.1, 0.2)) / float2(0.5, 0.2)) - 1.0) * 0.2, 0.2 - p.y);
    float spine = sd_seg(p, float2(0.42, 0.24), float2(0.26, 0.66)) - mix(0.028, 0.008, smoothstep(0.25, 0.66, p.y));
    float anal = sd_tri(p, float2(0.0, -0.2), float2(-0.3, -0.14), float2(-0.28, -0.46)) - 0.015;
    float pelv = sd_tri(p, float2(0.4, -0.22), float2(0.22, -0.24), float2(0.12, -0.52)) - 0.012;
    float fins = min(min(dors, spine), min(anal, pelv));
    float d = min(body, min(tail, fins));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = glow * exp(-max(d, 0.0) * 12.0) * edge;
    if (a < 0.002 && halo < 0.002) return float4(0.0);
    float3 violet = mix(col.rgb, float3(0.7, 0.35, 0.95), 0.75);
    float3 c3;
    if (body <= 0.0) {
        // warmer on the back, a paler, yellower belly; a speck on each scale
        c3 = mix(col.rgb * 1.08 + float3(0.1, 0.08, 0.0), col.rgb, smoothstep(-0.5, 0.3, b.y));
        float2 sg = p * float2(13.0, 15.0);
        sg.x += 0.5 * floor(sg.y);
        c3 *= 1.0 + 0.1 * (1.0 - smoothstep(0.1, 0.4, length(fract(sg) - 0.5))) * smoothstep(0.5, 0.3, p.x);
        // the violet streak, eye to flank
        float st = abs((p.y - 0.03) - (p.x - 0.62) * 0.5) - 0.02;
        c3 = mix(c3, violet, (1.0 - smoothstep(0.0, 0.015, st)) * step(0.3, p.x) * step(p.x, 0.66) * 0.8);
        c3 = fish_round(c3, b, body);
        c3 = fish_eye(c3, p, float2(0.63, 0.05), 0.075, violet, step(1.5, extra.w));
    } else if (tail < fins) {
        // the tail: the body's color at the stock, violet toward the trailing tips, clear in the web
        float along = smoothstep(0.0, -0.72, tq.x);
        c3 = mix(col.rgb * 0.95, violet, along * 0.7) * (0.9 + 0.1 * cos(atan2(tq.y, -tq.x) * 30.0));
        a *= lobes < web ? 0.92 : 0.6;
    } else {
        c3 = mix(col.rgb * 0.9, violet, 0.45 + 0.4 * step(spine, min(dors, min(anal, pelv)))) * (0.9 + 0.1 * cos(p.x * 70.0));
        a *= 0.85;
    }
    c3 += col.rgb * glow * 0.45;
    return float4((c3 * a + col.rgb * halo * (1.0 - a)) * col.a, (a + halo * (1.0 - a) * 0.55) * col.a);
}
