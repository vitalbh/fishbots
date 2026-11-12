// Open sea: the shark pup, the sardine and the dorado (fish kinds), and the tuna, the whale shark, the flying fish and the moon jelly.

// Sardine: a silver sliver with a blue-green back (the color it's given), a line of dark dots along the flank, a
// big bright gill plate, a deeply forked tail. The schools, and a session can be one. extra.w > 1.5: asleep.
float4 draw_ocean_sardine(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.8) * 0.05 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.3, 1.0, smoothstep(-0.9, -0.05, p.x));
    float ry = 0.2 * thin;
    float body = (length((p - float2(0.1, 0.0)) / float2(0.82, ry)) - 1.0) * ry;
    float2 tq = p - float2(-0.66, sin(phase - 1.2) * 0.05);
    float tail = max(sd_tri(tq, float2(0.08, 0.0), float2(-0.42, 0.3), float2(-0.42, -0.3)),
                     -sd_tri(tq, float2(-0.14, 0.0), float2(-0.5, 0.2), float2(-0.5, -0.2))) - 0.01;
    float dors = sd_tri(p, float2(0.1, 0.17), float2(-0.18, 0.16), float2(-0.1, 0.33)) - 0.012;
    float anal = sd_tri(p, float2(-0.2, -0.15), float2(-0.5, -0.08), float2(-0.44, -0.24)) - 0.01;
    float vent = sd_tri(p, float2(0.08, -0.18), float2(-0.08, -0.17), float2(-0.06, -0.28)) - 0.008;
    float fins = min(min(tail, vent), min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 back = mix(float3(0.1, 0.32, 0.45), col.rgb, 0.45) * 0.8, silver = float3(0.9, 0.94, 0.97);
    float yn = p.y / max(ry, 0.04);
    float3 c3 = mix(silver, back, smoothstep(0.05, 0.5, yn));
    // the dots along the flank, and a golden line over them
    float dots = 1.0 - smoothstep(0.014, 0.024, length(float2(fract(p.x * 7.0) - 0.5, (p.y - ry * 0.22) * 7.0) / 7.0));
    c3 = mix(c3, float3(0.08, 0.12, 0.2), dots * step(-0.5, p.x) * step(p.x, 0.4) * 0.7);
    c3 = mix(c3, float3(0.95, 0.85, 0.5), (1.0 - smoothstep(0.03, 0.12, abs(yn - 0.42))) * 0.35);
    c3 = fish_round(c3 * 1.1, float2((p.x - 0.1) / 0.82, yn), body);
    // the gill plate: a bright curve behind the eye
    float gc = abs(length((p - float2(0.6, 0.0)) * float2(1.0, 0.8)) - 0.13);
    c3 *= 1.0 - (1.0 - smoothstep(0.004, 0.016, gc)) * step(p.x, 0.6) * step(body, 0.0) * 0.25;
    float al = a;
    if (body > 0.0) { c3 = mix(back, silver, 0.45); al *= 0.6; }
    c3 = fish_eye(c3, p, float2(0.68, 0.035), 0.062, silver, extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// Dorado (mahi-mahi): a high, blunt forehead, a body tapering all the way to a slim tail stock, one long fin down the
// whole back, a deeply forked tail; gold and green with small blue spots, the back in the color it's given.
// extra.y: the pattern (0 gold, 1 bluer, 2 greener, 3 a pale one). extra.w > 1.5: asleep.
float4 draw_ocean_dorado(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    p.y -= sin(phase - p.x * 2.4) * 0.05 * smoothstep(0.3, -1.0, p.x);
    // deepest right behind the head, then a long taper
    float taper = mix(0.22, 1.0, smoothstep(-0.95, 0.45, p.x));
    float ry = 0.3 * taper;
    float body = (length((p - float2(0.02, -0.02)) / float2(0.9, ry)) - 1.0) * ry;
    float head = (length((p - float2(0.62, 0.02)) / float2(0.27, 0.3)) - 1.0) * 0.27;       // the blunt forehead
    body = smin_k(body, head, 0.08);
    float2 tq = p - float2(-0.78, -0.02 + sin(phase - 1.2) * 0.05);
    float tail = max(sd_tri(tq, float2(0.08, 0.0), float2(-0.36, 0.4), float2(-0.36, -0.4)),
                     -sd_tri(tq, float2(-0.06, 0.0), float2(-0.5, 0.3), float2(-0.5, -0.3))) - 0.012;
    // the long dorsal: from the forehead to the tail stock, tall in front, rippling
    float dy = 0.3 * mix(0.25, 1.0, smoothstep(-0.9, 0.5, p.x)) - 0.03;
    float dh = mix(0.05, 0.2, smoothstep(-0.8, 0.5, p.x)) * (1.0 + 0.08 * sin(p.x * 22.0 - phase * 1.4));
    float dors = max(max(p.y - (dy + dh), dy - 0.04 - p.y), max(p.x - 0.62, -0.72 - p.x));
    float anal = max(max(-(p.y + 0.02) - (0.3 * mix(0.25, 1.0, smoothstep(-0.9, 0.5, p.x)) + 0.08), p.y + 0.12), max(p.x + 0.05, -0.7 - p.x));
    float pang = -0.5 + sin(phase * 1.7) * 0.3;
    float2 pq = p - float2(0.42, -0.1);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.14, 0.0)) / float2(0.17, 0.045)) - 1.0) * 0.045;
    float fins = min(min(tail, pect), min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 gold = float3(1.0, 0.82, 0.2), green = float3(0.2, 0.7, 0.45), blue = float3(0.15, 0.5, 0.95);
    float3 back = mix(pat == 1 ? blue : green, col.rgb, 0.45);
    float3 side = pat == 3 ? float3(0.9, 0.92, 0.8) : mix(gold, back, pat == 2 ? 0.35 : 0.0);
    float yn = (p.y + 0.02) / max(ry, 0.05);
    float3 c3 = mix(side, back, smoothstep(0.0, 0.7, yn));
    c3 = mix(c3, float3(0.98, 0.95, 0.75), smoothstep(-0.4, -0.95, yn) * 0.6);                 // a pale belly
    float2 sg = p * 13.0;
    float spot = (1.0 - smoothstep(0.12, 0.2, length(fract(sg) - 0.5 - (float2(hash21(floor(sg)), hash21(floor(sg) + 3.0)) - 0.5) * 0.5)))
               * step(0.45, hash21(floor(sg) + 9.0));
    c3 = mix(c3, blue * 1.1 + 0.1, spot * 0.7);
    c3 = fish_round(c3 * 1.08, float2((p.x - 0.02) / 0.9, yn), body);
    // gill cover and mouth
    float gc = abs(length((p - float2(0.5, -0.04)) * float2(1.0, 0.75)) - 0.2);
    c3 *= 1.0 - (1.0 - smoothstep(0.005, 0.018, gc)) * step(p.x, 0.5) * step(body, 0.0) * 0.25;
    c3 = mix(c3, c3 * 0.3, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.14 + (p.x - 0.8) * 0.25) - 0.006)) * step(0.72, p.x) * step(body, 0.0));
    float al = a;
    if (body > 0.0) {
        bool isTail = tail < min(pect, min(dors, anal));
        float3 fin = isTail ? gold * 0.95 : mix(back * 0.8, blue, 0.35);
        float rays = isTail ? cos(atan2(tq.y, -tq.x) * 26.0) : cos(p.x * 70.0 + p.y * 20.0);
        c3 = fin * (0.85 + 0.15 * rays);
        al *= 0.8;
    }
    c3 = fish_eye(c3, p, float2(0.68, 0.05), 0.058, gold, extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}

// Tuna: a torpedo, dark blue above and silver below, sickle fins, a row of little yellow finlets down to a thin tail
// stock with keels, and a stiff crescent of a tail that beats fast. p = c * (1.8, 0.8). They pass in a small pack.
float4 draw_ocean_tuna(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.8, 0.8);
    p.y -= sin(phase * 1.4 - p.x * 2.0) * 0.03 * smoothstep(0.0, -1.5, p.x);
    float taper = mix(0.12, 1.0, smoothstep(-1.25, 0.1, p.x)) * mix(1.0, 0.6, smoothstep(0.7, 1.3, p.x));
    float ry = 0.36 * taper;
    float body = (length((p - float2(0.15, 0.0)) / float2(1.2, ry)) - 1.0) * ry;
    float2 tq = p - float2(-1.2, sin(phase * 1.4 - 1.0) * 0.06);
    float tail = max(sd_tri(tq, float2(0.1, 0.0), float2(-0.42, 0.56), float2(-0.42, -0.56)),
                     -(length((tq - float2(-0.62, 0.0)) / float2(0.5, 0.5)) - 1.0) * 0.5) - 0.01;      // a crescent
    float dors = sd_tri(p, float2(0.42, 0.3), float2(0.0, 0.3), float2(0.06, 0.62)) - 0.015;
    float dors2 = sd_tri(p, float2(-0.2, 0.26), float2(-0.42, 0.2), float2(-0.5, 0.6)) - 0.012;      // a tall sickle
    float anal = sd_tri(p, float2(-0.3, -0.25), float2(-0.52, -0.18), float2(-0.6, -0.56)) - 0.012;
    float2 pq = p - float2(0.55, -0.12);
    float pect = sd_tri(pq, float2(0.0, 0.03), float2(0.0, -0.03), float2(-0.5, -0.12 + 0.04 * sin(phase))) - 0.01;
    // finlets: little triangles above and below, back to the tail
    float fx = fract((p.x + 0.55) * 6.0) - 0.5;
    float fy = abs(p.y) - (0.36 * mix(0.12, 1.0, smoothstep(-1.25, 0.1, p.x)) + 0.01);
    float finlet = max(max(abs(fx) / 6.0 * 2.2 + fy - 0.04, -fy - 0.02), max(p.x + 0.55, -1.12 - p.x));
    float fins = min(min(tail, pect), min(min(dors, dors2), anal));
    float d = min(body, min(fins, finlet));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float lum = max(col.r, max(col.g, col.b));
    float3 navy = float3(0.06, 0.14, 0.3), silver = float3(0.86, 0.9, 0.95), yellow = float3(1.0, 0.82, 0.2);
    float yn = p.y / max(ry, 0.05);
    float3 c3 = mix(silver, navy, smoothstep(-0.05, 0.4, yn));
    c3 = mix(c3, yellow, (1.0 - smoothstep(0.03, 0.14, abs(yn - 0.02))) * 0.3 * step(p.x, 0.6));      // the golden line
    c3 = fish_round(c3 * 1.1, float2((p.x - 0.15) / 1.2, yn), body);
    float gc = abs(length((p - float2(0.82, -0.02)) * float2(1.0, 0.8)) - 0.22);
    c3 *= 1.0 - (1.0 - smoothstep(0.005, 0.02, gc)) * step(p.x, 0.82) * step(body, 0.0) * 0.22;
    c3 = mix(c3, c3 * 0.3, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.1 + (p.x - 1.2) * 0.2) - 0.006)) * step(1.1, p.x) * step(body, 0.0));
    if (body > 0.0) c3 = finlet < fins ? yellow : (min(dors2, anal) < min(min(tail, pect), dors) ? mix(navy, yellow, 0.55) : navy * 1.3);
    c3 = fish_eye(c3, p, float2(1.02, 0.05), 0.06, silver, 0.0);
    c3 *= lum;                                                                                          // the hour's light
    return float4(c3 * a, a);
}

// Whale shark, far away: a broad flat head and a wide mouth, a long body, grey-blue above with pale spots in rows and
// thin stripes, white below, a tall tail, a big first dorsal, long pectoral fins. p = c * (2.2, 0.7).
float4 draw_ocean_whaleshark(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.2, 0.7);
    p.y -= sin(phase * 0.5 - p.x * 1.3) * 0.045 * smoothstep(0.4, -2.0, p.x);
    float taper = mix(0.14, 1.0, smoothstep(-1.7, 0.2, p.x)) * mix(1.0, 0.72, smoothstep(1.0, 1.9, p.x));
    float ry = 0.3 * taper;
    float body = (length((p - float2(0.25, 0.0)) / float2(1.65, ry)) - 1.0) * ry;
    body = max(body, p.x - 1.84);                                                       // the flat front of the head
    float2 tq = p - float2(-1.5, sin(phase * 0.5 - 1.4) * 0.07);
    float tail = min(sd_tri(tq, float2(0.12, 0.0), float2(-0.2, 0.06), float2(-0.58, 0.6)),
                     sd_tri(tq, float2(0.12, 0.0), float2(-0.16, -0.05), float2(-0.42, -0.36))) - 0.015;
    float dors = sd_tri(p, float2(0.1, 0.27), float2(-0.4, 0.24), float2(-0.3, 0.6)) - 0.02;
    float dors2 = sd_tri(p, float2(-0.82, 0.14), float2(-1.05, 0.1), float2(-1.02, 0.28)) - 0.012;
    float pect = sd_tri(p, float2(0.95, -0.2), float2(0.55, -0.24), float2(0.3, -0.62 + 0.03 * sin(phase * 0.5))) - 0.02;
    float anal = sd_tri(p, float2(-0.85, -0.12), float2(-1.05, -0.08), float2(-1.0, -0.26)) - 0.012;
    float fins = min(min(tail, pect), min(min(dors, dors2), anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001) return float4(0.0);
    float yn = p.y / max(ry, 0.05);
    float3 grey = float3(0.28, 0.4, 0.52), white = float3(0.9, 0.93, 0.95);
    float3 c3 = mix(white, grey, smoothstep(-0.45, -0.1, yn));
    // the checkerboard: pale spots in rows, with thin pale bars between them
    float2 sg = float2(p.x * 9.0, yn * 3.2);
    float spot = 1.0 - smoothstep(0.16, 0.26, length(fract(sg) - 0.5));
    float bar = 1.0 - smoothstep(0.02, 0.06, abs(fract(p.x * 4.5) - 0.5));
    float top = smoothstep(-0.2, 0.05, yn);
    c3 = mix(c3, white, (spot * 0.75 + bar * 0.3) * top * step(body, 0.0));
    c3 = fish_round(c3, float2((p.x - 0.25) / 1.65, yn), body);
    // the ridges along the back, the mouth across the front, five gill slits
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, abs(yn - 0.5))) * 0.15 * step(body, 0.0);
    c3 = mix(c3, grey * 0.35, (1.0 - smoothstep(0.0, 0.014, abs(p.y + 0.02) - 0.008)) * step(1.6, p.x) * step(body, 0.0));
    float gs = abs(fract((p.x - 1.0) * 14.0) - 0.5);
    c3 *= 1.0 - (1.0 - smoothstep(0.08, 0.2, gs)) * step(1.0, p.x) * step(p.x, 1.36) * step(abs(yn + 0.05), 0.45) * step(body, 0.0) * 0.3;
    if (body > 0.0) c3 = grey * 0.9 * (0.8 + 0.3 * smoothstep(-0.4, 0.4, p.y));
    c3 = mix(c3, float3(0.02), (1.0 - smoothstep(0.016, 0.026, length(p - float2(1.62, 0.07)))) * step(body, 0.0));
    c3 *= col.rgb / max(0.001, max(col.r, max(col.g, col.b))) * max(col.r, max(col.g, col.b));
    return float4(c3 * a * col.a, a * col.a);
}

// Flying fish: it darts just under the surface (the water line at c.y = 0.6) and, while it moves, leaps clear of it
// in long glides, its wide pectoral fins spread like wings, the long lower lobe of its tail the last thing to leave
// the water. Resting, it hangs under the line with the wings folded. p = c * (1.5, 1.0).
float4 draw_ocean_flyingfish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 1.0);
    float moving = clamp(extra.w, 0.0, 1.0);
    // the glide: up out of the water and back, over and over while it goes
    float arc = max(0.0, sin(phase * 0.55));
    float lift = moving * arc;
    float y0 = mix(0.32, 0.8, lift);
    float tilt = moving * cos(phase * 0.55) * 0.25 * step(0.0, sin(phase * 0.55));
    float2 q = p - float2(0.0, y0);
    q = float2(q.x * cos(tilt) + q.y * sin(tilt), -q.x * sin(tilt) + q.y * cos(tilt));
    float wig = (1.0 - lift) * sin(phase * 2.0 - q.x * 3.0) * 0.03 * smoothstep(0.2, -1.0, q.x);
    q.y -= wig;
    float taper = mix(0.25, 1.0, smoothstep(-0.9, 0.0, q.x));
    float ry = 0.085 * taper;
    float body = (length((q - float2(0.1, 0.0)) / float2(0.8, ry)) - 1.0) * ry;
    float2 tq = q - float2(-0.66, 0.0);
    float tail = min(sd_tri(tq, float2(0.08, 0.0), float2(-0.1, 0.02), float2(-0.3, 0.2)),
                     sd_tri(tq, float2(0.08, 0.0), float2(-0.1, -0.02), float2(-0.46, -0.3))) - 0.008;     // the lower lobe longer
    // the wings: long pectoral fins, spread wide in the air, folded along the body in the water
    float spread = mix(0.12, 1.0, smoothstep(0.15, 0.6, lift));
    float wing = sd_tri(q, float2(0.42, 0.02), float2(0.2, 0.0), float2(-0.35, 0.1 + 0.42 * spread)) - 0.01;
    float wing2 = sd_tri(q, float2(0.42, -0.02), float2(0.22, -0.02), float2(-0.3, -0.06 - 0.2 * spread)) - 0.008;
    float pelv = sd_tri(q, float2(-0.2, -0.04), float2(-0.36, -0.03), float2(-0.5, -0.06 - 0.16 * spread)) - 0.008;
    float fins = min(min(tail, pelv), min(wing, wing2));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 blue = mix(float3(0.12, 0.3, 0.6), col.rgb, 0.3), silver = float3(0.9, 0.94, 0.97);
    float yn = q.y / max(ry, 0.03);
    float3 c3 = mix(silver, blue, smoothstep(-0.1, 0.5, yn));
    c3 = fish_round(c3 * 1.1, float2((q.x - 0.1) / 0.8, yn), body);
    float al = a;
    if (body > 0.0) {
        bool isWing = min(wing, wing2) < min(tail, pelv);
        // the wings are clear, with fine rays and a faint blue
        c3 = isWing ? mix(float3(0.75, 0.88, 1.0), blue, 0.25) * (0.85 + 0.15 * cos(atan2(q.y, -(q.x - 0.4)) * 60.0)) : blue * 0.9;
        al *= isWing ? 0.62 : 0.85;
    }
    c3 = fish_eye(c3, q, float2(0.7, 0.012), 0.04, silver, 0.0);
    // under the line the water takes a little of it; where it breaks the surface, a ring of spray
    float under = smoothstep(0.62, 0.56, p.y);
    c3 = mix(c3, c3 * float3(0.6, 0.8, 0.95), under * 0.4);
    float lum = max(col.r, max(col.g, col.b));
    float spray = moving * (1.0 - smoothstep(0.0, 0.35, lift)) * exp(-pow((p.y - 0.6) / 0.03, 2.0)) * exp(-pow(p.x / 0.5, 2.0)) * 0.5;
    return float4((c3 * al + float3(0.85, 0.95, 1.0) * spray * (1.0 - al)) * lum, al + spray * (1.0 - al) * 0.5);
}

// Moon jelly: a clear, shallow dome with four pale rings inside (the color it's given), a fringe of fine short
// tentacles, four frilly arms hanging from the middle; it pulses as it drifts. p = c.
float4 draw_ocean_moonjelly(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float pulse = sin(phase * 1.3 + extra.y * 6.0);
    float w = 0.72 + 0.07 * pulse, h = 0.42 - 0.05 * pulse;
    float2 b = (p - float2(0.0, 0.18)) / float2(w, h);
    float dome = (length(b) - 1.0) * h;
    dome = max(dome, -(p.y - 0.12 - 0.04 * pulse));                                   // open underneath
    float aa = fwidth(dome) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, dome);
    float3 glass = float3(0.75, 0.88, 1.0), ring = mix(float3(0.95, 0.7, 0.9), col.rgb, 0.5);
    float rim = 1.0 - smoothstep(0.0, 0.06, -dome);
    float3 c3 = glass * (0.45 + 0.65 * rim);
    float alpha = inside * (0.22 + 0.5 * rim);
    // the four rings, seen through the bell
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 ctr = float2((fmod(fi, 2.0) - 0.5) * 0.5 * w, 0.3 + (floor(fi / 2.0) - 0.5) * 0.22 * (h / 0.42));
        float r = abs(length((p - ctr) / float2(0.2 * w, 0.085)) - 0.75);
        float rg = (1.0 - smoothstep(0.1, 0.3, r)) * inside;
        c3 = mix(c3, ring, rg * 0.8);
        alpha = max(alpha, rg * 0.65);
    }
    // the fringe and the arms below
    float fringe = 0.0;
    float fx = p.x / w;
    if (abs(fx) < 1.0 && p.y < 0.16 && p.y > -0.2) {
        float strand = 1.0 - smoothstep(0.1, 0.35, abs(fract(fx * 14.0 + sin(p.y * 20.0 + phase * 1.5) * 0.15) - 0.5));
        fringe = strand * smoothstep(-0.16, 0.12, p.y) * 0.35;
    }
    float arms = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float x = (fi - 1.5) * 0.17 + sin(phase * 0.9 + p.y * 6.0 + fi * 1.7) * 0.05 * smoothstep(0.1, -0.8, p.y);
        float wd = 0.055 * smoothstep(-0.85, -0.1, p.y) * (0.75 + 0.25 * sin(p.y * 40.0 + fi * 2.0));
        arms = max(arms, (1.0 - smoothstep(wd * 0.5, wd, abs(p.x - x))) * step(p.y, 0.14) * smoothstep(-0.9, -0.7, p.y));
    }
    float3 soft = mix(glass, ring, 0.35);
    c3 = mix(c3, soft, (1.0 - inside) * step(0.001, max(fringe, arms * 0.5)));
    alpha = max(alpha, max(fringe, arms * 0.42) * (1.0 - inside));
    float edge = 1.0 - smoothstep(0.55, 1.0, max(abs(c.x), abs(c.y)));
    float halo = (0.12 + glow * 0.6) * exp(-max(dome, 0.0) * 7.0) * edge * (1.0 - inside) * step(0.1, p.y);
    float lum = max(col.r, max(col.g, col.b));
    return float4((c3 * alpha + ring * halo * 0.5) * lum * col.a, (alpha + halo * 0.25) * col.a);
}

// Shark pup: a young shark, small and round-nosed, with eyes too big for it. The back in the color it's given, a
// white belly with the line between them wavering along the flank, a tall first dorsal fin, long pectoral fins, a
// tail with the upper lobe longer, five gill slits. extra.y: the pattern (0 plain, 1 black tips on the fins, 2
// leopard spots, 3 tiger stripes). extra.w: fullness, + 2 while asleep.
float4 draw_ocean_sharkpup(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    int pat = int(extra.y + 0.5) % 4;
    bool asleep = extra.w > 1.5;
    float fat = clamp(extra.w - (asleep ? 2.0 : 0.0), 0.0, 1.0);
    // a shark swims with its whole body: a slow wave, widest at the tail
    p.y -= sin(phase - p.x * 2.2) * 0.055 * smoothstep(0.5, -1.0, p.x);
    float taper = mix(0.16, 1.0, smoothstep(-0.95, 0.15, p.x)) * mix(1.0, 0.62, smoothstep(0.45, 1.0, p.x));
    float ry = 0.23 * taper * (1.0 + 0.3 * fat);
    float body = (length((p - float2(0.1, 0.0)) / float2(0.92, ry)) - 1.0) * ry;
    float2 tq = p - float2(-0.74, sin(phase - 1.5) * 0.06);
    float tail = min(sd_tri(tq, float2(0.1, 0.0), float2(-0.1, 0.03), float2(-0.42, 0.44)),
                     sd_tri(tq, float2(0.1, 0.0), float2(-0.08, -0.03), float2(-0.3, -0.26))) - 0.014;
    float dors = sd_tri(p, float2(0.22, 0.19), float2(-0.14, 0.17), float2(-0.1, 0.52)) - 0.02;
    float dors2 = sd_tri(p, float2(-0.44, 0.1), float2(-0.6, 0.07), float2(-0.6, 0.2)) - 0.01;
    float pang = sin(phase * 0.9) * 0.08;
    float pect = sd_tri(p, float2(0.4, -0.15), float2(0.12, -0.17), float2(0.0, -0.5 + pang)) - 0.018;
    float pelv = sd_tri(p, float2(-0.3, -0.12), float2(-0.46, -0.09), float2(-0.5, -0.24)) - 0.01;
    float fins = min(min(tail, pect), min(min(dors, dors2), pelv));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 back = mix(float3(0.34, 0.45, 0.56), col.rgb, 0.55), white = float3(0.95, 0.96, 0.97);
    float yn = p.y / max(ry, 0.05);
    // the line between back and belly dips behind the gills and wavers
    float edgeY = -0.12 + 0.12 * sin(p.x * 6.0 + 1.0) * smoothstep(0.6, 0.0, p.x) - 0.25 * smoothstep(0.5, 0.9, p.x);
    float3 c3 = mix(white, back, smoothstep(edgeY - 0.12, edgeY + 0.12, yn));
    float top = smoothstep(edgeY, edgeY + 0.3, yn);
    if (pat == 2) {
        float2 sg = p * 12.0;
        c3 = mix(c3, back * 0.4, (1.0 - smoothstep(0.16, 0.26, length(fract(sg) - 0.5 - (float2(hash21(floor(sg)), hash21(floor(sg) + 3.0)) - 0.5) * 0.4)))
                                  * step(0.4, hash21(floor(sg) + 7.0)) * top * 0.8);
    }
    if (pat == 3) c3 = mix(c3, back * 0.45, (1.0 - smoothstep(0.1, 0.22, abs(fract(p.x * 4.5 + 0.1 * sin(p.y * 9.0)) - 0.5))) * top * smoothstep(-0.2, 0.3, yn) * 0.7);
    c3 = fish_round(c3 * 1.08, float2((p.x - 0.1) / 0.92, yn), body);
    // gill slits, a little smile under the snout, a nostril
    float gs = abs(fract((p.x - 0.36) * 22.0) - 0.5);
    c3 *= 1.0 - (1.0 - smoothstep(0.1, 0.22, gs)) * step(0.36, p.x) * step(p.x, 0.58) * step(abs(yn + 0.05), 0.5) * step(body, 0.0) * 0.3;
    float2 m = p - float2(0.72, -0.1);
    c3 = mix(c3, float3(0.25, 0.12, 0.14), (1.0 - smoothstep(0.0, 0.012, abs(length(m / float2(1.0, 0.7)) - 0.1) - 0.006)) * step(m.y, -0.02) * step(body, 0.0) * 0.85);
    c3 = mix(c3, back * 0.4, (1.0 - smoothstep(0.008, 0.016, length(p - float2(0.95, -0.01)))) * step(body, 0.0) * 0.7);
    float al = a;
    if (body > 0.0) {
        c3 = back * (0.82 + 0.25 * smoothstep(-0.4, 0.5, p.y));
        // black tips: the ends of the fins dipped in ink
        if (pat == 1) {
            float tip = max(max(smoothstep(0.34, 0.46, p.y) * step(dors, 0.02), smoothstep(-0.34, -0.46, p.y) * step(pect, 0.02)),
                            max(smoothstep(0.22, 0.36, tq.y), smoothstep(-0.14, -0.24, tq.y)) * step(tail, 0.02));
            c3 = mix(c3, float3(0.05, 0.05, 0.07), tip);
        }
        c3 = mix(c3, c3 * 1.25 + 0.05, smoothstep(-0.04, 0.0, d) * 0.5);
    }
    // the eye: big, dark and round, with a wide shine (a pup's)
    c3 = fish_eye(c3, p, float2(0.74, 0.05), 0.07, float3(0.3, 0.4, 0.5), asleep ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}
