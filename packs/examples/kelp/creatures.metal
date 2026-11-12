// Kelp forest creatures: the garibaldi, the sheephead, the sea otter and the sea lion.

// Garibaldi: a deep-bodied damselfish, bright orange all over, a rounded tail. As a fish kind it keeps a little of
// the project's color (col); pattern 1 is the juvenile, darker with blue spots.
float4 draw_kelp_garibaldi(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.2) * 0.04 * smoothstep(0.2, -1.0, p.x);
    // a deep oval body narrowing into the tail stock
    float thin = mix(0.42, 1.0, smoothstep(-0.75, -0.1, p.x));
    float body = (length((p - float2(0.1, 0.0)) / float2(0.72, 0.46 * thin)) - 1.0) * 0.4;
    // one long soft dorsal fin hugging the back, the anal fin below, both rounded at the back
    float back = (length((p - float2(-0.1, 0.02)) / float2(0.66, 0.6)) - 1.0) * 0.4;
    float dors = max(back, max(0.2 - p.y, p.x - 0.32));
    float anal = max((length((p - float2(-0.2, -0.04)) / float2(0.5, 0.5)) - 1.0) * 0.4, max(p.y + 0.18, p.x - 0.12));
    // the tail: a stock, then a wide fan, slightly notched
    float2 tq = p - float2(-0.62, sin(phase - 1.0) * 0.04);
    float stock = sd_box(tq - float2(0.02, 0.0), float2(0.1, 0.12), 0.04);
    float fan = max((length((tq - float2(-0.16, 0.0)) / float2(0.26, 0.36)) - 1.0) * 0.2, tq.x + 0.02 - 0.0);
    fan = max(fan, -((length((tq - float2(-0.5, 0.0)) / float2(0.14, 0.12)) - 1.0) * 0.1));
    float tail = min(stock, fan);
    float d = min(min(body, tail), min(dors, anal));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    int pat = int(extra.y + 0.5) % 8;
    float3 orange = mix(float3(1.0, 0.45, 0.08), col.rgb, 0.2);
    float3 c3 = orange;
    if (pat == 1) {                                                  // juvenile: deeper red-orange with blue spots
        c3 = float3(0.85, 0.32, 0.08);
        float2 sg = p * 9.0;
        float spot = (1.0 - smoothstep(0.18, 0.3, length(fract(sg) - 0.5))) * step(0.55, hash21(floor(sg)));
        c3 = mix(c3, float3(0.2, 0.55, 1.0), spot * step(body, 0.0));
    }
    // scales catching the light, fins a little more see-through and darker at the edge
    float2 sc = p * float2(16.0, 20.0);
    c3 *= 0.96 + 0.05 * smoothstep(0.25, 0.5, length(fract(sc + float2(floor(sc.y) * 0.5, 0.0)) - 0.5)) * step(body, 0.0);
    if (min(min(dors, anal), tail) < body) {
        c3 *= 0.8;
        c3 *= 0.9 + 0.1 * sin(atan2(p.y, p.x + 0.2) * 40.0);         // fin rays
    }
    if (body < min(min(dors, anal), tail)) c3 = fish_round(c3 * 1.1, (p - float2(0.1, 0.0)) / float2(0.72, 0.46 * thin), body);
    else c3 *= 0.75 + 0.35 * smoothstep(-0.5, 0.5, p.y);
    c3 = mix(c3, float3(1.0, 0.8, 0.5), (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25 * step(0.0, p.y));
    // gill cover, a little mouth, and the eye (asleep, extra.w > 1.5, a line)
    c3 *= 1.0 - (1.0 - smoothstep(0.006, 0.02, abs(length((p - float2(0.5, -0.02)) * float2(1.0, 0.7)) - 0.2))) * step(p.x, 0.5) * step(body, 0.0) * 0.22;
    c3 = mix(c3, c3 * 0.35, (1.0 - smoothstep(0.0, 0.012, abs(p.y + 0.09 + (p.x - 0.76) * 0.3) - 0.006)) * step(0.7, p.x) * step(body, 0.0));
    c3 = fish_eye(c3, p, float2(0.54, 0.11), 0.062, float3(1.0, 0.75, 0.2), extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float halo = exp(-max(d, 0.0) * 18.0) * glow * 0.4 * (1.0 - a);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.2;
    return float4((c3 * a + orange * halo) * col.a, (a + halo * 0.5) * col.a);
}

// California sheephead (a male): a big wrasse with a black head and tail, a red middle, a white chin, a bumpy
// forehead and buck teeth, the urchin eater. Lives around the barren.
float4 draw_kelp_sheephead(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.4, 0.8);
    p.y -= sin(phase - p.x * 2.0) * 0.05 * smoothstep(0.2, -1.1, p.x);
    float body = (length((p - float2(0.0, 0.0)) / float2(0.95, 0.42)) - 1.0) * 0.4;
    float head = (length((p - float2(0.72, 0.06)) / float2(0.36, 0.36)) - 1.0) * 0.3;            // the forehead bump
    body = smin_k(body, head, 0.1);
    float dors = max((length((p - float2(-0.1, 0.36)) / float2(0.8, 0.14)) - 1.0) * 0.12, -(p.y - 0.32));
    float anal = max((length((p - float2(-0.3, -0.34)) / float2(0.45, 0.13)) - 1.0) * 0.12, p.y + 0.3);
    float2 tq = p - float2(-0.92, sin(phase - 1.0) * 0.05);
    float tail = max(sd_tri(tq, float2(0.06, 0.0), float2(-0.38, 0.28), float2(-0.38, -0.28)), -(tq.x + 0.42)) - 0.01;
    float pect = (length((p - float2(0.28, -0.08)) / float2(0.18, 0.07)) - 1.0) * 0.06;
    float d = min(min(body, tail), min(min(dors, anal), pect));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 black = float3(0.06, 0.05, 0.06), red = float3(0.78, 0.22, 0.2), white = float3(0.92, 0.9, 0.86);
    // black head, red middle, black tail end (the boundaries soft and a little ragged)
    float edgeN = 0.04 * vnoise(p * 6.0);
    float3 c3 = mix(black, red, smoothstep(0.42 + edgeN, 0.34 + edgeN, p.x));
    c3 = mix(c3, black, smoothstep(-0.48 + edgeN, -0.58 + edgeN, p.x));
    if (min(dors, anal) < body || tail < body) c3 = mix(c3, black, 0.6);
    // the white chin and the teeth
    float chin = length((p - float2(0.82, -0.18)) / float2(0.22, 0.12)) - 1.0;
    c3 = mix(c3, white, (1.0 - smoothstep(-0.1, 0.05, chin)) * step(body, 0.0));
    c3 = mix(c3, float3(0.97), (1.0 - smoothstep(0.0, 0.012, sd_box(p - float2(1.06, -0.04), float2(0.025, 0.035), 0.008))));
    // scales and round shading
    float2 sc = p * float2(12.0, 15.0);
    c3 *= 0.9 + 0.12 * smoothstep(0.2, 0.5, length(fract(sc + float2(floor(sc.y) * 0.5, 0.0)) - 0.5));
    if (body < min(min(dors, anal), min(tail, pect))) c3 = fish_round(c3 * 1.1 + 0.015, p / float2(0.95, 0.42), body);
    else c3 = c3 * (0.8 + 0.35 * smoothstep(-0.45, 0.45, p.y)) + 0.03;
    c3 = fish_eye(c3, p, float2(0.82, 0.14), 0.055, float3(0.95, 0.15, 0.1), 0.0);            // a red eye
    c3 *= col.rgb / max(0.001, max(col.r, max(col.g, col.b)));                                 // the hour's light
    return float4(c3 * a, a);
}

// Sea otter, floating on its back at the surface (the water line at c.y ≈ 0.6): belly up, head at the right end
// with a pale face, paws on its chest working at an urchin, tail and hind feet at the left; bobbing with the waves.
float4 draw_kelp_otter(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.6, 0.8);
    float bob = sin(phase * 1.3 + extra.y * 6.0) * 0.03;
    p.y -= bob;
    float wl = 0.48;
    float body = (length((p - float2(-0.05, wl)) / float2(0.85, 0.27)) - 1.0) * 0.2;
    float head = (length((p - float2(0.88, wl + 0.08)) / float2(0.24, 0.2)) - 1.0) * 0.18;
    float tail = (length((p - float2(-1.05, wl + 0.02)) / float2(0.35, 0.07)) - 1.0) * 0.06;
    float feet = (length((p - float2(-0.8, wl + 0.16)) / float2(0.1, 0.06)) - 1.0) * 0.05;
    float pawsY = wl + 0.2 + 0.03 * sin(phase * 4.0);                                            // working at its snack
    float paws = (length((p - float2(0.42, pawsY)) / float2(0.12, 0.07)) - 1.0) * 0.06;
    float urchin = length(p - float2(0.32, pawsY + 0.05)) - 0.06;
    float d = smin_k(smin_k(body, head, 0.08), tail, 0.05);
    d = min(min(d, feet), paws);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, min(d, urchin));
    float3 fur = col.rgb;
    float3 c3 = fur * (0.65 + 0.5 * smoothstep(wl - 0.15, wl + 0.25, p.y));
    c3 = mix(c3, fur * 1.35 + 0.05, smoothstep(wl + 0.12, wl + 0.24, p.y) * step(abs(p.x), 0.6) * 0.5);   // the paler chest
    c3 *= 0.9 + 0.15 * vnoise(p * float2(40.0, 12.0));                                         // fur
    float face = length((p - float2(0.92, wl + 0.08)) / float2(0.2, 0.17)) - 1.0;
    c3 = mix(c3, float3(0.85, 0.78, 0.66) * dot(col.rgb, float3(0.7)), (1.0 - smoothstep(-0.2, 0.1, face)) * step(head, 0.0));
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.022, 0.03, length(p - float2(0.95, wl + 0.14))));   // eye
    c3 = mix(c3, float3(0.08), 1.0 - smoothstep(0.03, 0.04, length(p - float2(1.08, wl + 0.1))));    // nose
    c3 = mix(c3, fur * 0.6, (1.0 - smoothstep(-0.005, 0.005, min(paws, feet))) * 0.3);                // darker paws and feet
    if (urchin < 0.0 && urchin < d) {
        float ang = atan2(p.y - pawsY - 0.05, p.x - 0.32);
        c3 = float3(0.35, 0.14, 0.45) * (0.7 + 0.4 * step(0.5, fract(ang * 4.0)));
    }
    // under the water line the water veils it
    float under = smoothstep(wl + 0.02, wl - 0.05, p.y);
    c3 = mix(c3, c3 * float3(0.6, 0.85, 0.85), under * 0.5);
    float aw = a * (1.0 - under * 0.25);
    return float4(c3 * aw, aw);
}

// Sea lion: sleek and fast, a brown torpedo with long front flippers, a small head with whiskers and a little ear,
// hind flippers trailing. Used by the passing sea lion and by the theme's look for the shark (a presence).
float4 draw_kelp_sealion(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.8, 0.7);
    float sw = sin(phase * 1.2);
    p.y -= sw * 0.05 * smoothstep(-0.2, -1.5, p.x);
    float body = (length((p - float2(-0.05, 0.0)) / float2(1.15, 0.27 * mix(0.45, 1.0, smoothstep(-1.3, -0.1, p.x)))) - 1.0) * 0.25;
    float head = (length((p - float2(1.15, 0.06)) / float2(0.3, 0.18)) - 1.0) * 0.15;
    float neck = sd_seg(p, float2(0.7, 0.02), float2(1.0, 0.05)) - 0.17;
    float d = smin_k(smin_k(body, neck, 0.1), head, 0.08);
    float2 fp = p - float2(0.45, -0.15);
    float fa = -0.9 + sw * 0.35;
    fp = float2(fp.x * cos(fa) - fp.y * sin(fa), fp.x * sin(fa) + fp.y * cos(fa));
    float flip = (length((fp - float2(0.3, 0.0)) / float2(0.38, 0.09)) - 1.0) * 0.07;
    float2 hp = p - float2(-1.2, 0.0);
    float hind = min((length((hp - float2(-0.2, 0.05 + sw * 0.05)) / float2(0.25, 0.06)) - 1.0) * 0.05,
                     (length((hp - float2(-0.2, -0.05 + sw * 0.05)) / float2(0.25, 0.06)) - 1.0) * 0.05);
    d = min(min(d, flip), hind);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 c3 = col.rgb * (0.6 + 0.55 * smoothstep(-0.3, 0.3, p.y));                            // darker below the light
    c3 = mix(c3, col.rgb * 1.25, smoothstep(0.05, 0.22, p.y) * step(body, 0.02) * 0.4);      // a wet sheen on the back
    if (min(flip, hind) < min(body, head) || (flip < 0.0)) c3 = col.rgb * 0.45 * (0.8 + 0.3 * smoothstep(-0.1, 0.1, fp.y));
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.025, 0.035, length(p - float2(1.2, 0.12))));          // eye
    c3 = mix(c3, col.rgb * 0.5, 1.0 - smoothstep(0.012, 0.022, length(p - float2(1.0, 0.18))));        // ear
    c3 = mix(c3, float3(0.1), 1.0 - smoothstep(0.02, 0.03, length(p - float2(1.42, 0.07))));            // nose
    for (int i = 0; i < 3; i++) {                                                                       // whiskers
        float wy = 0.0 - 0.025 * float(i);
        float wd = sd_seg(p, float2(1.36, wy), float2(1.55, wy - 0.04 + 0.02 * float(i)));
        c3 = mix(c3, float3(0.85), (1.0 - smoothstep(0.003, 0.007, wd)) * 0.6);
        a = max(a, (1.0 - smoothstep(0.003, 0.007, wd)) * 0.6);
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.2;
    c3 += col.rgb * glow * 0.3;
    float halo = exp(-max(d, 0.0) * 22.0) * glow * 0.45 * (1.0 - a);
    return float4((c3 * a + col.rgb * halo) * col.a, (a + halo * 0.5) * col.a);
}

// Señorita: a small cigar-shaped wrasse, orange above and cream below, a pointed snout with buck teeth, a black
// blotch at the base of the tail. The kelp forest's schools. col tints it; extra.w > 1.5: asleep.
float4 draw_kelp_senorita(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= sin(phase - p.x * 2.6) * 0.045 * smoothstep(0.3, -1.0, p.x);
    float thin = mix(0.5, 1.0, smoothstep(-0.9, -0.1, p.x)) * mix(1.0, 0.55, smoothstep(0.45, 0.95, p.x));   // a pointed snout
    float ry = 0.17 * thin;
    float body = (length((p - float2(0.08, 0.0)) / float2(0.88, ry)) - 1.0) * ry;
    float2 tq = p - float2(-0.72, sin(phase - 1.2) * 0.04);
    float tail = max(sd_tri(tq, float2(0.08, 0.0), float2(-0.34, 0.25), float2(-0.34, -0.25)), length(tq - float2(0.06, 0.0)) - 0.32) - 0.01;
    // one long low dorsal fin along the back, one anal fin below
    float dors = max((length((p - float2(-0.1, 0.12)) / float2(0.6, 0.12)) - 1.0) * 0.12, 0.12 - p.y);
    float anal = max((length((p - float2(-0.3, -0.12)) / float2(0.32, 0.1)) - 1.0) * 0.1, p.y + 0.12);
    float fins = min(tail, min(dors, anal));
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 orange = mix(float3(0.95, 0.55, 0.15), col.rgb, 0.3), cream = float3(0.98, 0.9, 0.7);
    float yn = p.y / max(ry, 0.03);
    float3 c3 = mix(cream, orange, smoothstep(-0.5, 0.15, yn));
    float2 sc = p * float2(18.0, 22.0);
    c3 *= 0.94 + 0.08 * smoothstep(0.25, 0.5, length(fract(sc + float2(floor(sc.y) * 0.5, 0.0)) - 0.5));     // scales
    c3 = mix(c3, float3(0.05, 0.04, 0.05), (1.0 - smoothstep(0.7, 1.0, length((p - float2(-0.64, 0.0)) / float2(0.1, 0.12)))) * 0.9);   // the blotch
    c3 = fish_round(c3 * 1.08, float2((p.x - 0.08) / 0.88, yn), body);
    float al = a;
    if (body > 0.0) { c3 = orange * 0.85 * (0.9 + 0.1 * cos(p.x * 60.0)); al *= 0.75; }
    c3 = fish_eye(c3, p, float2(0.62, 0.035), 0.05, float3(1.0, 0.8, 0.3), extra.w > 1.5 ? 1.0 : 0.0);
    c3 += col.rgb * glow * 0.45;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - a) * fade;
    return float4((c3 * al + col.rgb * halo * 0.9) * col.a, min(al + halo * 0.55, 1.0) * col.a);
}
