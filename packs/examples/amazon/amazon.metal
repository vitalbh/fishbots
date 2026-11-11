// Amazon river: the flooded forest far behind, and what sits in the tank: a sunken branch, giant water lilies, a
// Marajoara urn (the chest), dead leaves and a Brazil nut pod on the litter, bits of leaf adrift.

float amazon_s_ell(float2 p, float2 ce, float2 r) {
    return (length((p - ce) / r) - 1.0) * min(r.x, r.y);
}

// A limb: a segment whose thickness goes from ra to rb.
float amazon_s_limb(float2 p, float2 a, float2 b, float ra, float rb) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}

// The igapó, the flooded forest: trunks standing in the water in two rows, the far one almost gone in the tea-colored
// haze, their buttresses flaring out at the bottom and prop roots reaching down beside them; lianas sagging between
// the crowns and thin aerial roots hanging from above, swaying; a bank of roots and litter along the bottom.
// uv 0…1 over the window (y up).
float4 draw_amazon_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float asp = extra.x;
    float lit = 0.4 + 0.6 * light;
    float yy = uv.y - extra.z;
    if (yy < -0.03) return float4(0.0);
    float4 o = float4(0.0);
    for (int layer = 0; layer < 2; layer++) {
        float fl = float(layer);                                          // 0: the far row, 1: the nearer one
        float x = (uv.x + gaze.x * (0.004 + 0.007 * fl)) * asp + fl * 3.7;
        float w = 0.3 + 0.16 * fl;
        float3 bark = mix(water, float3(0.13, 0.075, 0.03) * lit, 0.26 + 0.24 * fl);
        float al = 0.55 + 0.27 * fl;
        float cell0 = floor(x / w);
        for (int j = -1; j <= 1; j++) {
            float cell = cell0 + float(j);
            float h1 = hash21(float2(cell, 3.0 + fl * 9.0)), h2 = hash21(float2(cell, 5.0 + fl * 9.0)), h3 = hash21(float2(cell, 8.0 + fl * 9.0));
            if (h3 < 0.22) continue;                                      // a gap in the row
            float r = (0.011 + 0.017 * h2) * (1.0 + 0.7 * fl);
            float x0 = (cell + 0.25 + 0.5 * h1) * w + (h2 - 0.5) * 0.07 * yy + 0.005 * sin(yy * 9.0 + h1 * 30.0);
            float dx = x - x0;
            if (abs(dx) > 0.13) continue;
            float flare = r * (1.0 + 3.2 * exp(-max(yy, 0.0) * (15.0 - 4.0 * h1)));          // the buttress
            float k = 1.0 - smoothstep(flare - 0.002, flare + 0.001, abs(dx));
            // prop roots: two legs leaving the trunk and reaching the bottom on either side
            float2 q = float2(dx, yy);
            float legs = min(amazon_s_limb(q, float2(r * 0.5, 0.2 + 0.1 * h1), float2(0.05 + 0.05 * h2, -0.02), r * 0.3, r * 0.2),
                             amazon_s_limb(q, float2(-r * 0.5, 0.14 + 0.1 * h2), float2(-0.04 - 0.05 * h1, -0.02), r * 0.3, r * 0.2));
            k = max(k, (1.0 - smoothstep(-0.001, 0.0015, legs)) * step(0.4, h3));
            float3 c3 = bark * (0.82 + 0.3 * clamp(-dx / flare, -1.0, 1.0)) * (0.9 + 0.2 * vnoise(float2(dx * 110.0, yy * 14.0 + cell)));
            c3 = mix(c3, water, smoothstep(0.35, 1.0, uv.y) * 0.35);                         // lost in the glare up high
            o = mix(o, float4(c3, 1.0) * al, k);
        }
    }
    float xn = (uv.x + gaze.x * 0.011) * asp;
    float3 vine = mix(water, float3(0.14, 0.1, 0.03) * lit, 0.5);
    // lianas: ropes sagging between the crowns
    float lw = 0.75;
    for (int j = 0; j <= 1; j++) {
        float hh = hash21(float2(floor(xn / lw + 0.5 * float(j)), 21.0 + float(j)));
        float u = (fract(xn / lw + 0.5 * float(j)) - 0.5) * 2.0;
        float sag = 0.16 + 0.3 * hh;
        float ly = 1.04 - sag * (1.0 - u * u) + 0.004 * sin(t * 0.5 + hh * 20.0 + u * 3.0);
        float slope = 2.0 * sag * abs(u) / (lw * 0.5) / asp;
        float th = 0.0022 * sqrt(1.0 + slope * slope * asp * asp);
        float k = (1.0 - smoothstep(th * 0.5, th, abs(uv.y - ly))) * step(0.3, hh);
        o = mix(o, float4(vine, 1.0) * 0.75, k);
    }
    // aerial roots hanging from above
    float rw = 0.085;
    float rc = floor(xn / rw);
    float rh = hash21(float2(rc, 31.0));
    if (rh > 0.45) {
        float len = 0.1 + 0.42 * hash21(float2(rc, 37.0));
        float down = 1.0 - uv.y;
        if (down < len) {
            float tt = down / len;
            float rx = (rc + 0.2 + 0.6 * hash21(float2(rc, 41.0))) * rw + sin(t * 0.4 + rh * 40.0) * 0.006 * tt * tt;
            float k = 1.0 - smoothstep(0.0006, 0.0018, abs(xn - rx));
            o = mix(o, float4(vine, 1.0) * 0.65, k * (1.0 - 0.5 * tt));
        }
    }
    // the bank: roots and litter heaped along the bottom
    float bh = 0.025 + 0.045 * vnoise(float2(xn * 3.0, 1.7)) + 0.02 * vnoise(float2(xn * 11.0, 4.2));
    if (yy < bh) {
        float top = smoothstep(bh - 0.03, bh, yy);
        float3 c3 = mix(water, float3(0.1, 0.06, 0.025) * lit, 0.55) * (0.8 + 0.3 * top) * (0.85 + 0.3 * vnoise(float2(xn * 40.0, yy * 40.0)));
        o = mix(o, float4(c3, 1.0), 0.85);
    }
    return o;
}

float amazon_wood(float2 p, float k, float g) {
    float2 a = float2(-1.9, g + 0.0), b = float2(-0.55, g + 0.1 + 0.05 * k), cc = float2(0.7, g + 0.4 + 0.1 * k);
    float d = amazon_s_limb(p, a, b, 0.2, 0.17);
    d = smin_k(d, amazon_s_limb(p, b, cc, 0.17, 0.11), 0.06);
    d = smin_k(d, amazon_s_limb(p, cc, float2(1.75, g + 0.72 + 0.2 * k), 0.11, 0.04), 0.05);
    d = smin_k(d, amazon_s_limb(p, cc, float2(1.2 + 0.25 * k, g + 1.1), 0.075, 0.03), 0.05);
    float2 f = float2(-0.25 - 0.3 * k, g + 0.78);
    d = smin_k(d, amazon_s_limb(p, b, f, 0.085, 0.055), 0.05);
    d = smin_k(d, amazon_s_limb(p, f - float2(0.02, 0.1), float2(0.2 - 0.2 * k, g + 1.15), 0.04, 0.018), 0.03);
    d = smin_k(d, amazon_s_limb(p, a, float2(-2.03, g + 0.36), 0.1, 0.04), 0.06);        // root stubs at the butt
    d = smin_k(d, amazon_s_limb(p, a + float2(0.2, 0.0), float2(-1.6, g + 0.3), 0.06, 0.03), 0.05);
    return d;
}

// A sunken branch: a trunk lying half buried in the litter, rising into bare forks, its bark furrowed, with knots,
// algae growing on the top of it. p = c * (2.2, 0.8); the sand line is at p.y = -0.48 ("bury": 0.2) and it fades
// into the sand below. extra.y: the seed (which way it lies, how the forks rise).
float4 draw_amazon_driftwood(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.2, 0.8);
    float seed = extra.y;
    if (fract(seed * 3.17) > 0.5) p.x = -p.x;
    float k = fract(seed * 7.7);
    float g = -0.48;
    float d = amazon_wood(p, k, g);
    if (d > 0.05) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float up = clamp((amazon_wood(p + float2(0.0, 0.035), k, g) - d) / 0.035, -1.0, 1.0);     // > 0 on the top side
    float round = clamp(-d / 0.1, 0.0, 1.0);
    float3 wood = col.rgb;
    float grain = vnoise(float2(p.x * 5.0 + p.y * 3.0, p.y * 30.0 - p.x * 12.0 + seed * 9.0));
    float3 c3 = wood * (0.72 + 0.4 * grain);
    c3 = mix(c3, wood * 0.4, smoothstep(0.62, 0.8, vnoise(p * float2(9.0, 22.0) + seed * 5.0)) * 0.6);   // furrows
    for (int i = 0; i < 3; i++) {                                                             // knots
        float fi = float(i);
        float2 kc = float2(-1.2 + 1.0 * fi + 0.3 * fract(seed * (3.0 + fi)), g + 0.06 + 0.2 * fi * (0.8 + 0.4 * k));
        float kr = length((p - kc) / float2(0.07, 0.045));
        c3 = mix(c3, wood * 0.3, (1.0 - smoothstep(0.5, 0.75, abs(kr - 1.0) + 0.5)) * 0.0 + (1.0 - smoothstep(0.35, 0.6, kr)) * 0.75);
        c3 = mix(c3, wood * 1.25, (1.0 - smoothstep(0.1, 0.25, abs(kr - 0.95))) * 0.3);
    }
    c3 *= 0.5 + 0.35 * round + 0.4 * max(up, 0.0);                                            // lit from above
    c3 *= 1.0 - 0.35 * max(-up, 0.0);
    float moss = smoothstep(0.25, 0.75, up) * smoothstep(0.35, 0.65, vnoise(p * 5.0 + seed * 3.0));
    c3 = mix(c3, float3(0.2, 0.3, 0.1) * dot(col.rgb, float3(0.9)) * (0.7 + 0.6 * vnoise(p * 40.0)), moss * 0.7);
    c3 += float3(1.0, 0.85, 0.6) * (1.0 - smoothstep(0.0, 0.025, -d)) * max(up, 0.0) * 0.12 * dot(col.rgb, float3(0.6));
    c3 *= 0.6 + 0.4 * smoothstep(g - 0.04, g + 0.16, p.y);                                    // darker toward the litter
    a *= smoothstep(g - 0.2, g - 0.02, p.y);
    return float4(c3 * a, a);
}

// Giant water lily (vitória-régia): a pad like a tray, its rim turned up all around (green inside, wine-red and ribbed
// outside), floating at the surface, the stalk going down into the dark; beside some of them (by seed) a flower
// open on the water, white or turning pink, or a bud. p = c * (1.9, 0.8); the water line is at p.y = 0.12.
float4 draw_amazon_victoria(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.9, 0.8);
    float seed = extra.y;
    float side = fract(seed * 5.3) > 0.5 ? 1.0 : -1.0;
    p.x *= side;
    float kind = fract(seed * 7.13);                       // < 0.45 a flower, < 0.7 a bud, else only the pad
    bool flower = kind < 0.45, bud = kind >= 0.45 && kind < 0.7;
    float cx = (flower || bud) ? 0.45 : 0.0;
    float rx = (flower || bud) ? 1.25 : 1.55;
    float y0 = 0.13, hr = 0.115, ry = 0.14;
    float2 q = float2(p.x - cx, p.y);
    float dBot = amazon_s_ell(q, float2(0.0, y0), float2(rx, ry));
    float dTop = amazon_s_ell(q, float2(0.0, y0 + hr), float2(rx, ry));
    float wall = max(abs(q.x) - rx, abs(q.y - y0 - hr * 0.5) - hr * 0.5);
    float pad = min(min(dBot, dTop), wall);
    // the stalk, down into the water, swaying
    float sx = sin(t * 0.4 + seed * 9.0) * 0.08 * (0.1 - p.y);
    float stem = max(abs(q.x - 0.1 - sx) - 0.028, max(p.y - 0.1, -p.y - 0.78));
    // the flower or the bud, on the water beside the pad
    float2 fp = p - float2(-1.42, 0.12);
    float petals = 1e3, core = 1e3;
    float petalId = 0.0;
    if (flower) {
        for (int i = -4; i <= 4; i++) {
            float an = float(i) * 0.37 + 0.03 * sin(t * 0.6 + float(i));
            float2 pq = float2(fp.x * cos(an) - fp.y * sin(an), fp.x * sin(an) + fp.y * cos(an));
            float len = 0.29 - 0.02 * abs(float(i));
            float pd = amazon_s_ell(pq, float2(0.0, len), float2(0.085, len));
            if (pd < petals) { petals = pd; petalId = float(i); }
        }
        petals = max(petals, -fp.y - 0.03);
        core = amazon_s_ell(fp, float2(0.0, 0.1), float2(0.14, 0.12));
    } else if (bud) {
        petals = amazon_s_ell(fp, float2(0.0, 0.17), float2(0.13, 0.22));
        petals = max(petals, -fp.y - 0.03);
        petals = min(petals, max(abs(fp.x) - 0.024, max(fp.y, -fp.y - 0.6)));          // its own stalk
    }
    float d = min(min(pad, stem), petals);
    if (d > 0.04) return float4(0.0);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = dot(col.rgb, float3(0.55));
    float3 green = col.rgb;
    float3 wine = float3(0.78, 0.16, 0.22) * lum * 1.7;
    float3 c3;
    if (petals < 0.0 && petals <= pad) {
        float hgt = clamp(fp.y / 0.55, 0.0, 1.0);
        float pink = fract(seed * 11.7) > 0.5 ? 1.0 : 0.0;
        float3 lightC = float3(1.0, 0.98, 0.93), deepC = mix(float3(0.98, 0.88, 0.74), float3(0.95, 0.42, 0.6), pink);
        c3 = mix(deepC, lightC, smoothstep(0.1, 0.9, hgt)) * (0.9 - 0.06 * fmod(abs(petalId), 2.0));
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -petals)) * 0.22;                         // each petal's edge
        if (bud) {
            c3 = mix(green * 0.8 / max(lum * 1.25, 0.01), float3(0.97, 0.86, 0.84), smoothstep(0.3, 0.75, hgt)) * (0.86 + 0.14 * cos(fp.x * 70.0));
            if (fp.y < 0.0) { c3 = green * 0.5 / max(lum * 1.25, 0.01); a *= 0.5 + 0.5 * smoothstep(-0.6, -0.05, fp.y); }
        }
        if (flower && core < 0.0) c3 = mix(c3, float3(0.98, 0.6, 0.4), 0.55);
        c3 *= min(1.0, lum * 1.7);                                                        // the hour's light
    } else if (pad < 0.0) {
        if (dTop < 0.0) {
            if (dBot > 0.0) {
                c3 = green * 1.3 * (0.9 + 0.1 * cos(q.x * 60.0));                         // the far wall, catching light
            } else {
                // the floor of the tray: veins fanning from the middle, crossed by rings
                float2 fq = float2(q.x / rx, (q.y - y0) / ry);
                float ang = atan2(fq.y, fq.x), rr = length(fq);
                float veins = max(1.0 - smoothstep(0.0, 0.1, abs(fract(ang * 3.5) - 0.5) * rr), 1.0 - smoothstep(0.0, 0.06, abs(fract(rr * 3.0) - 0.5)));
                c3 = green * (0.82 + 0.25 * smoothstep(-0.8, 0.8, fq.y)) * (1.0 - 0.2 * veins);
                c3 += float3(1.0, 0.95, 0.7) * pow(max(0.0, 1.0 - length((q - float2(-0.35, y0 + 0.02)) / float2(0.55, 0.045))), 3.0) * 0.25 * lum;
                c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -dBot)) * smoothstep(0.0, -0.5, fq.y) * 0.35;   // the near wall's shadow
            }
            c3 = mix(c3, green * 1.55 + 0.04, 1.0 - smoothstep(0.0, 0.014, -dTop));        // the lip
        } else {
            // the outside of the rim: wine-red, ribbed
            float rib = 0.5 + 0.5 * cos(asin(clamp(q.x / rx, -1.0, 1.0)) * 30.0);
            c3 = wine * (0.72 + 0.32 * rib) * (0.7 + 0.5 * smoothstep(y0 - ry, y0 + hr, q.y));
            c3 = mix(c3, green * 0.9, smoothstep(0.015, 0.0, -dTop) * 0.4);
        }
    } else {
        c3 = mix(wine, green, 0.35) * (0.45 + 0.4 * smoothstep(-0.78, 0.1, p.y));
        c3 *= 0.85 + 0.25 * step(0.5, fract(p.y * 14.0));                                  // the stalk's prickles
        a *= 0.35 + 0.65 * smoothstep(-0.78, -0.2, p.y);
    }
    // what's under the water line is veiled by the water
    if (pad < 0.0 || petals < 0.0) c3 *= 1.0 - 0.25 * smoothstep(0.1, 0.03, p.y);
    return float4(c3 * a, a);
}

// A Marajoara funerary urn in place of the treasure chest: a big-bellied pot of cream slip painted in red and black
// (a band of square spirals around the belly, zigzags on the neck), two lugs, a lid with a knob, leaning in the
// litter. As a replaced chest, extra.y is how open it is: the lid lifts and tips, and gold light comes out (glow).
// p = c * (0.85, 1.0); the ground is at p.y = -0.9.
float4 draw_amazon_urn(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.85, 1.0);
    float open = clamp(extra.y, 0.0, 1.0);
    float lean = 0.1;
    float2 r0 = p - float2(0.0, -0.9);
    p = float2(r0.x * cos(lean) - r0.y * sin(lean), r0.x * sin(lean) + r0.y * cos(lean)) + float2(0.03, -0.9);
    float belly = amazon_s_ell(p, float2(0.0, -0.42), float2(0.6, 0.5));
    float nw = 0.3 + 0.1 * smoothstep(0.22, 0.36, p.y) + 0.08 * smoothstep(0.1, -0.05, p.y);
    float neck = max(abs(p.x) - nw, max(p.y - 0.36, -p.y - 0.1));
    float pot = smin_k(belly, neck, 0.04);
    float lugs = min(amazon_s_ell(p, float2(0.6, -0.2), float2(0.08, 0.1)), amazon_s_ell(p, float2(-0.6, -0.2), float2(0.08, 0.1)));
    pot = min(pot, lugs);
    // the lid: a low dome with a knob; open, it lifts and tips back
    float2 lp = p - float2(-0.38, 0.37);
    float la = -open * 0.55;
    lp = float2(lp.x * cos(la) - lp.y * sin(la), lp.x * sin(la) + lp.y * cos(la)) - float2(0.38, open * 0.1);
    float lid = max(amazon_s_ell(lp, float2(0.0, 0.0), float2(0.42, 0.2)), -lp.y);
    lid = min(lid, amazon_s_ell(lp, float2(0.0, 0.23), float2(0.08, 0.07)));
    lid = min(lid, sd_box(lp - float2(0.0, 0.0), float2(0.43, 0.025), 0.02));
    float d = min(pot, lid);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 slip = col.rgb;
    float3 red = float3(0.62, 0.2, 0.1) * dot(col.rgb, float3(0.42));
    float3 black = float3(0.1, 0.07, 0.06) * dot(col.rgb, float3(0.42));
    float3 c3 = slip;
    float sx = asin(clamp(p.x / 0.6, -1.0, 1.0));                                    // around the belly
    if (pot < lid) {
        c3 = slip * (0.9 + 0.12 * vnoise(p * 14.0));
        // the belly band: square spirals between two lines
        float by = (p.y + 0.36) / 0.2;
        if (abs(by) < 1.0) {
            float2 cellp = float2(fract(sx * 1.9 + 0.5) - 0.5, by * 0.5);
            float ring = max(abs(cellp.x), abs(cellp.y)) * 2.0;
            float sq = step(0.5, fract(ring * 2.6 + 0.25)) * step(ring, 0.92);
            float notch = step(abs(cellp.y - 0.12), 0.05) * step(0.0, cellp.x);          // opens the squares into a spiral
            c3 = mix(c3, red, sq * (1.0 - notch));
        }
        c3 = mix(c3, black, 1.0 - smoothstep(0.012, 0.025, abs(abs(by) - 1.08) * 0.2));
        // zigzags on the neck, a red lip
        float zy = (p.y - 0.14) / 0.09;
        float zig = abs(abs(fract(p.x * 5.0) - 0.5) * 2.0 - 0.5 - zy * 0.5);
        if (abs(zy) < 1.0 && neck < 0.0) c3 = mix(c3, black, 1.0 - smoothstep(0.1, 0.2, zig));
        c3 = mix(c3, red, step(0.29, p.y) * step(neck, 0.0));
        c3 = mix(c3, red, smoothstep(-0.74, -0.8, p.y) * 0.8);                             // the red foot
        if (lugs < 0.0 && lugs < belly) c3 = red * 1.1;
        float2 q = (p - float2(0.0, -0.3)) / float2(0.62, 0.7);
        float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
        float li = dot(n, normalize(float3(-0.35, 0.75, 0.5)));
        c3 *= 0.55 + 0.6 * li;
        c3 += float3(1.0, 0.95, 0.85) * pow(max(0.0, li), 10.0) * 0.12 * dot(col.rgb, float3(0.5));
        // algae creeping up from the litter, and the contact shadow
        float alg = smoothstep(-0.45, -0.85, p.y + 0.15 * vnoise(p * 6.0));
        c3 = mix(c3, float3(0.16, 0.2, 0.08) * dot(col.rgb, float3(0.5)), alg * 0.55);
        c3 *= 0.55 + 0.45 * smoothstep(-0.92, -0.7, p.y);
    } else {
        c3 = slip * (0.9 + 0.12 * vnoise(lp * 14.0));
        float rings = step(0.5, fract(length(lp * float2(1.0, 2.0)) * 7.0));
        c3 = mix(c3, red, rings * step(0.03, lp.y) * 0.9);
        if (lp.y < 0.03) c3 = black * 1.6;
        float2 q = lp / float2(0.45, 0.24);
        float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
        c3 *= 0.6 + 0.55 * dot(n, normalize(float3(-0.35, 0.75, 0.5)));
    }
    // the light inside: in the gap under the lid and spilling over the lip
    float2 gp = p - float2(0.05, 0.4);
    float gapLight = open * exp(-dot(gp / float2(0.4, 0.14 + 0.1 * open), gp / float2(0.4, 0.14 + 0.1 * open)) * 1.6);
    float3 gold = float3(1.0, 0.8, 0.35);
    c3 += gold * gapLight * (0.5 + 0.5 * glow) * 0.8 * a;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = (gapLight * 0.6 + glow * exp(-max(d, 0.0) * 9.0) * 0.5) * edge * (1.0 - a) * max(open, glow);
    return float4(c3 * a + gold * halo, min(1.0, a + halo * 0.55));
}

// A dead leaf lying on the bottom (the litter that makes the water black): a pointed blade with its midrib, curled
// a little, brown, ochre or rust by its seed. p = c * (1.0, 0.6); the ground at p.y = -0.54.
float4 draw_amazon_leaf(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.6);
    float seed = extra.y;
    if (fract(seed * 4.3) > 0.5) p.x = -p.x;
    p.y -= -0.26 + 0.1 * p.x * (fract(seed * 2.1) - 0.3) + 0.12 * smoothstep(0.3, 0.9, p.x) * fract(seed * 6.7);   // the tip curls up
    float R = 1.75, k = 1.52 - 0.12 * fract(seed * 8.9);
    float d = max(length(p - float2(0.0, k)) - R, length(p - float2(0.0, -k)) - R);
    d = min(d, sd_seg(p, float2(-0.85, 0.0), float2(-0.98, -0.03)) - 0.02);          // the stalk
    float a = 1.0 - smoothstep(-0.03, 0.03, d);
    float h = fract(seed * 12.9);
    float3 base = mix(col.rgb, col.rgb * float3(1.25, 0.95, 0.5), smoothstep(0.3, 0.7, h));
    base = mix(base, col.rgb * float3(0.6, 0.45, 0.4), smoothstep(0.75, 0.95, h));
    float3 c3 = base * (0.7 + 0.5 * smoothstep(-0.25, 0.25, p.y));
    c3 *= 1.0 - (1.0 - smoothstep(0.015, 0.05, abs(p.y))) * 0.4;                       // the midrib
    c3 *= 0.88 + 0.14 * cos((abs(p.y) * 2.0 - p.x) * 22.0);                            // the side veins
    c3 *= 0.8 + 0.3 * vnoise(p * 9.0 + seed * 20.0);
    c3 += col.rgb * glow * 0.3;
    return float4(c3 * a * col.a, a * col.a);
}

// A Brazil nut pod (ouriço): a woody ball the size of a fist, rough, with the little hole where it hung, half sunk
// in the litter. p = c * (1.0, 0.85); the ground at p.y ≈ -0.77.
float4 draw_amazon_nut(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.85);
    float seed = extra.y;
    float2 ce = float2(0.0, -0.2);
    float d = amazon_s_ell(p, ce, float2(0.72, 0.62));
    d = max(d, -p.y - 0.78);
    float a = 1.0 - smoothstep(-0.03, 0.03, d);
    float2 q = (p - ce) / float2(0.72, 0.62);
    float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
    float li = dot(n, normalize(float3(-0.3, 0.8, 0.5)));
    float3 c3 = col.rgb * (0.75 + 0.5 * vnoise(p * 7.0 + seed * 30.0)) * (0.5 + 0.7 * li);
    float2 hp = (p - ce - float2(0.2 * (fract(seed * 3.3) - 0.5), 0.36)) / float2(0.2, 0.11);
    c3 = mix(c3, col.rgb * 0.2, 1.0 - smoothstep(0.6, 1.0, length(hp)));               // the hole on top
    c3 = mix(c3, col.rgb * 1.5, (1.0 - smoothstep(0.1, 0.3, abs(length(hp) - 1.2))) * 0.4);
    c3 *= 0.6 + 0.4 * smoothstep(-0.8, -0.5, p.y);
    c3 += col.rgb * glow * 0.3;
    return float4(c3 * a * col.a, a * col.a);
}

// A bit of leaf adrift in the water (the theme's marine snow): a small pointed blade, tumbling slowly.
float4 draw_amazon_leafbit(float2 c, float t, float glow, float4 col, float4 extra) {
    float ang = t * (0.3 + extra.y * 0.5) + extra.y * 6.28;
    float2 p = float2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
    p.y *= 1.0 + 0.6 * (0.5 + 0.5 * sin(t * 0.8 + extra.y * 9.0));                     // it turns: wider, narrower
    float R = 1.3, k = 0.98;
    float d = max(length(p - float2(0.0, k)) - R, length(p - float2(0.0, -k)) - R);
    float a = 1.0 - smoothstep(-0.08, 0.08, d);
    float3 c3 = mix(float3(0.62, 0.36, 0.14), float3(0.9, 0.66, 0.24), fract(extra.y * 7.7)) * (0.6 + 0.4 * col.rgb);
    c3 *= 1.0 - (1.0 - smoothstep(0.03, 0.1, abs(p.y))) * 0.3;
    return float4(c3 * a * col.a, a * col.a);
}
