/// Drawings: the music fish and its notes, the presences plugins keep in the tank, the deep-sea visitors, frost.
let shaderPresences = #"""
float3 hue3(float h) { return clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }

float4 draw_betta(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    float t = phase;
    // body: small and rounded, at the front
    float body = length((p - float2(0.42, 0.0)) / float2(0.34, 0.2)) - 1.0;
    // the tail: a big fan behind, its edge rippling
    float2 q = p - float2(0.12, 0.0);
    float ang = atan2(q.y, -q.x);
    float r = length(q);
    float edge = 0.78 + 0.07 * sin(ang * 9.0 - t * 1.6) + 0.05 * sin(ang * 4.0 + t * 0.9);
    float tail = max(r - edge, abs(ang) - 1.15);
    tail = max(tail, q.x - 0.05);
    // dorsal and anal fins, long and wavy
    float2 d = p - float2(0.25, 0.16);
    float dorsal = max(length(d / float2(0.28, 0.2 + 0.03 * sin(t * 1.3 + p.x * 8.0))) - 1.0, -d.y);
    float2 a = p - float2(0.25, -0.16);
    float anal = max(length(a / float2(0.3, 0.22 + 0.03 * sin(t * 1.1 + p.x * 7.0))) - 1.0, a.y);
    float fins = min(min(tail * 0.6, dorsal * 0.15), anal * 0.15);
    float dist = min(body * 0.2, fins);
    float aa = fwidth(dist) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, dist);
    // color: the fish's own on the body; the fins shimmer through the rainbow, slowly
    float3 base = col.rgb;
    float shimmer = 0.5 + 0.5 * sin(t * 0.7);
    float3 fin = mix(base, hue3(fract(dot(base, float3(0.3, 0.5, 0.2)) + r * 0.6 + t * 0.05)) * 0.9, 0.55 * shimmer + 0.25);
    float onFin = smoothstep(-0.02, 0.02, body * 0.2 - fins);
    float3 c3 = mix(base * (0.8 + 0.35 * (1.0 - length(p - float2(0.42, 0.06)) * 2.0)), fin, onFin);
    c3 *= 0.85 + 0.15 * sin(ang * 18.0) * onFin;                       // the fin rays
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.035, 0.05, length(p - float2(0.6, 0.05))));   // eye
    c3 += base * glow * 0.5;
    float aOut = inside * col.a * mix(1.0, 0.82, onFin);
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(dist, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    return float4(c3 * aOut + base * halo * 0.9, min(aOut + halo * 0.55, 1.0));
}

float4 draw_note(float2 c, float glow, float4 col) {
    float2 p = c;
    float head = length((float2(p.x + 0.2, p.y + 0.45) * float2(1.0, 1.35))) - 0.27;
    float stem = sd_box(p - float2(0.05, 0.1), float2(0.05, 0.55), 0.02);
    float2 fp = p - float2(0.1, 0.55);
    float flag = max(abs(length(fp - float2(0.28, -0.05)) - 0.26) - 0.05, -fp.x);
    flag = max(flag, fp.y - 0.1);
    float d = min(min(head, stem), flag);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    float halo = exp(-max(d, 0.0) * 9.0) * 0.6;
    float a = (inside + halo * (1.0 - inside)) * glow;
    return float4(col.rgb * a, a * 0.9);
}

// ---------- presences (Scene.swift): creatures and objects that plugins control, sprite kinds 25–30 ----------
// Every drawing returns premultiplied color; `col` is already tinted by the state, `glow` is the state's halo.

// the state's halo fades out well before the quad's edge (otherwise it shows as a blurred rectangle)
float edge_fade(float2 c) { return 1.0 - smoothstep(0.45, 0.9, max(abs(c.x), abs(c.y))); }

float4 presence_out(float d, float3 c3, float glow, float3 tint, float alpha, float2 c) {
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    float halo = exp(-max(d, 0.0) * 24.0) * glow * 0.45 * (1.0 - inside) * edge_fade(c);
    return float4((c3 * inside + tint * halo) * alpha, (inside + halo * 0.5) * alpha);
}

// shark (25): a grey torpedo with a tall dorsal fin, a crescent tail and a pale belly; faces +x
float4 draw_shark(float2 c, float phase, float glow, float4 col, float hammer = 0.0) {
    float2 p = c * float2(1.6, 0.7);
    float sway = sin(phase * 2.2);
    p.y -= sway * 0.06 * smoothstep(0.2, -1.3, p.x);                       // the back half follows the tail
    // a torpedo: pointed snout, deepest behind the gills, a slim tail stock
    float thin = mix(0.3, 1.0, smoothstep(-1.1, 0.1, p.x)) * mix(1.0, 0.72, smoothstep(0.55, 1.25, p.x));
    float body = (length((p - float2(0.08, 0.0)) / float2(1.22, 0.31 * thin)) - 1.0) * 0.28;
    // a hammerhead: the snout ends in a wide flat head, an eye at each end
    float2 eyeAt = float2(1.0, 0.055);
    if (hammer > 0.5) {
        body = max(body, p.x - 0.98);
        float neck = sd_seg(p, float2(0.7, -0.01), float2(1.1, -0.01)) - 0.075;
        float bar = sd_seg(p, float2(1.13, -0.24), float2(1.13, 0.22)) - 0.055 - 0.02 * smoothstep(0.2, -0.2, p.y);
        body = smin_k(body, smin_k(neck, bar, 0.08), 0.06);
        eyeAt = float2(1.15, 0.24);
    }
    // the tail: a long upper lobe and a shorter lower one
    float2 tp = p - float2(0.0, sway * 0.08);
    float tail = min(sd_tri(tp, float2(-0.95, 0.03), float2(-1.55, 0.52), float2(-1.2, -0.02)),
                     sd_tri(tp, float2(-0.98, -0.02), float2(-1.42, -0.3), float2(-1.18, 0.02))) - 0.015;
    // fins: a tall swept-back dorsal with a hollow trailing edge, a second small one, a long pectoral, the pelvic
    float dorsal = max(sd_tri(p, float2(-0.18, 0.22), float2(0.3, 0.26), float2(-0.28, 0.66 + hammer * 0.12)),
                       -(length(p - float2(-0.42, 0.52)) - 0.2)) - 0.012;
    float dorsal2 = sd_tri(p, float2(-0.78, 0.1), float2(-0.62, 0.12), float2(-0.84, 0.24)) - 0.008;
    float pang = sin(phase * 1.1) * 0.04;
    float pectoral = max(sd_tri(p, float2(0.18, -0.17), float2(0.5, -0.19), float2(-0.04, -0.56 - pang)),
                         -(length(p - float2(-0.12, -0.38)) - 0.16)) - 0.012;
    float pelvic = sd_tri(p, float2(-0.55, -0.12), float2(-0.42, -0.14), float2(-0.62, -0.26)) - 0.008;
    float fins = min(min(dorsal, dorsal2), min(pectoral, pelvic));
    float d = min(min(body, tail), fins);
    // countershading: a dark back, a pale belly, the line between them ragged
    float line = -0.04 + 0.03 * sin(p.x * 9.0) + 0.02 * vnoise(p * 8.0);
    float belly = smoothstep(line + 0.02, line - 0.05, p.y) * step(body, 0.0);
    float3 back = col.rgb * (0.8 + 0.2 * vnoise(p * 5.0));
    float3 c3 = mix(back, float3(0.88, 0.9, 0.92) * dot(col.rgb, float3(0.45)) * 1.7, belly * 0.9);
    // round shading and a rim of light along the back
    float yn = p.y / max(0.31 * thin, 0.05);
    c3 *= 0.7 + 0.4 * smoothstep(-1.0, 0.8, yn);
    if (body < 0.0) c3 += float3(0.75, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.03, -body)) * smoothstep(0.0, 0.8, yn) * 0.25;
    if (fins < 0.0 && body >= 0.0) c3 = back * (0.75 + 0.3 * smoothstep(-0.5, 0.6, p.y));
    // five gill slits, curved; the mouth underneath; a dark eye with a glint
    for (int i = 0; i < 5; i++) {
        float x = 0.56 + float(i) * 0.05 - p.y * p.y * 2.0;
        c3 *= 1.0 - 0.45 * (1.0 - smoothstep(0.006, 0.014, abs(p.x - x))) * step(abs(p.y + 0.02), 0.11) * step(body, 0.0);
    }
    float mouth = abs(p.y + 0.11 + (p.x - 1.0) * 0.12) - 0.005;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.01, mouth)) * step(0.86, p.x) * step(p.x, 1.1) * 0.35 * (1.0 - hammer);
    float re = length(p - eyeAt);
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.03, 0.042, re));
    c3 = mix(c3, float3(0.9), 1.0 - smoothstep(0.004, 0.01, length(p - eyeAt - float2(0.008, 0.01))));
    if (hammer > 0.5) c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.025, 0.036, length(p - float2(1.15, -0.25))));   // the far eye
    return presence_out(d, c3, glow, col.rgb, col.a, c);
}

// submarine (26): a rounded hull with a tower, periscope, glowing portholes and a spinning propeller; faces +x
float4 draw_submarine(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(1.5, 0.75);
    float hull = sd_seg(p, float2(-0.85, 0.0), float2(0.85, 0.0)) - 0.3 + 0.08 * smoothstep(0.2, -0.95, p.x);
    float tower = sd_box(p - float2(0.12, 0.36), float2(0.26, 0.13), 0.06);
    float scope = min(sd_seg(p, float2(0.24, 0.48), float2(0.24, 0.66)), sd_seg(p, float2(0.24, 0.66), float2(0.38, 0.66))) - 0.028;
    float blade = sd_box(p - float2(-1.26, 0.0), float2(0.045, 0.24 * abs(cos(phase * 9.0)) + 0.03), 0.02);
    float hub = sd_seg(p, float2(-1.2, 0.0), float2(-0.95, 0.0)) - 0.04;
    float d = min(min(hull, tower), min(scope, min(blade, hub)));
    float3 c3 = col.rgb * (0.65 + 0.45 * smoothstep(-0.3, 0.3, p.y));
    c3 = mix(c3, col.rgb * 0.55, step(abs(p.y + 0.08), 0.025) * step(hull, 0.0));          // a seam along the hull
    if (blade < 0.0 || hub < 0.0) c3 = float3(0.5, 0.48, 0.42);
    float lamp = 0.0;
    for (int i = 0; i < 3; i++) {
        float r = length(p - float2(-0.4 + float(i) * 0.38, 0.03));
        lamp = max(lamp, 1.0 - smoothstep(0.07, 0.09, r));
        c3 = mix(c3, float3(0.25, 0.22, 0.18), (1.0 - smoothstep(0.09, 0.11, r)) * step(0.085, r));
    }
    float3 light = float3(1.0, 0.85, 0.5) * (0.55 + 0.45 * sin(phase * 1.7));
    c3 = mix(c3, light, lamp);
    return presence_out(d, c3, glow, col.rgb, col.a, c);
}

// bottle (27): green glass lying on the sand with a rolled message inside; the message glows with the state
float4 draw_bottle(float2 c, float phase, float glow, float4 col, float deep = 0.0) {
    float2 p = c * float2(0.9, 0.5);
    float a = 0.16;
    p = float2(p.x * cos(a) + p.y * sin(a), -p.x * sin(a) + p.y * cos(a));
    float body = sd_seg(p, float2(-0.5, 0.0), float2(0.18, 0.0)) - 0.2;
    float neck = sd_seg(p, float2(0.18, 0.0), float2(0.62, 0.0)) - 0.075;
    float glass = min(body, neck);
    float cork = sd_box(p - float2(0.7, 0.0), float2(0.08, 0.07), 0.02);
    float paper = sd_box(p - float2(-0.16, -0.01), float2(0.26, 0.085), 0.04);
    // the deep sea's: barnacles crusting the glass along the top and around the neck
    float barn = 1e3;
    if (deep > 0.5) {
        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            float2 bc = i < 4 ? float2(-0.5 + fi * 0.2, 0.2 - 0.03 * fract(fi * 0.618)) : float2(0.28 + (fi - 4.0) * 0.17, 0.08);
            barn = min(barn, length((p - bc) / float2(1.0, 0.85)) - (0.05 + 0.02 * fract(fi * 0.37)));
        }
        glass = min(glass, barn);
    }
    float d = min(glass, cork);
    float aa = fwidth(d) + 1e-4;
    float inG = 1.0 - smoothstep(-aa, aa, glass);
    float rim = smoothstep(-0.05, 0.0, glass) * inG;
    float shine = (1.0 - smoothstep(0.0, 0.03, abs(p.y - 0.11))) * step(p.x, 0.1) * step(-0.45, p.x) * inG;
    float inP = (1.0 - smoothstep(-aa, aa, paper)) * inG * (1.0 - deep);
    float3 c3 = col.rgb * (0.85 + 0.5 * rim) * inG;
    float alphaG = inG * (0.55 + 0.4 * rim);
    float3 paperC = float3(0.95, 0.9, 0.75) * (1.0 + glow * (0.8 + 0.4 * sin(phase * 4.0)));
    c3 = mix(c3, paperC, inP * 0.9);
    alphaG = max(alphaG, inP * 0.95);
    c3 += float3(1.0) * shine * 0.6 * (1.0 - deep * 0.7);
    if (deep > 0.5) {
        // dark old glass, and instead of the message a swirl of glowing plankton in the state's color
        float inB = 1.0 - smoothstep(-aa, aa, barn);
        // a barnacle: a pale ridged cone, lit on top, with a dark opening in the middle
        float3 shellC = float3(0.62, 0.58, 0.5) * (0.65 + 0.5 * smoothstep(-0.05, 0.0, barn)) * (0.85 + 0.3 * vnoise(p * 40.0));
        shellC *= 1.0 - 0.75 * (1.0 - smoothstep(0.0, 0.02, -barn - 0.03));
        c3 = mix(c3 * 0.45 + float3(0.02, 0.03, 0.02) * inG, shellC, inB);
        alphaG = max(alphaG * 0.85, inB);
        float2 sp = p + float2(sin(phase * 0.7 + p.y * 9.0) * 0.03, cos(phase * 0.9 + p.x * 7.0) * 0.02);
        float2 cell = floor(sp * 16.0), f = fract(sp * 16.0);
        float2 at = float2(hash21(cell), hash21(cell + 7.3)) * 0.6 + 0.2 + 0.1 * float2(sin(phase + cell.x), cos(phase * 1.3 + cell.y));
        float dots = (1.0 - smoothstep(0.08, 0.2, length(f - at))) * step(0.45, hash21(cell + 3.1))
                   * (0.6 + 0.4 * sin(phase * 2.0 + hash21(cell) * 6.28)) * (1.0 - smoothstep(-0.02, 0.0, body + 0.03));
        float3 plank = mix(float3(0.45, 1.0, 0.9), col.rgb * 1.6, 0.6) * (0.5 + glow * 1.5) * (0.75 + 0.25 * sin(phase * 3.0));
        c3 += plank * dots;
        c3 += plank * 0.12 * (1.0 - smoothstep(-0.02, 0.0, body + 0.03));
    }
    float inC = 1.0 - smoothstep(-aa, aa, cork);
    c3 = mix(c3, float3(0.6, 0.42, 0.25), inC);
    float al = max(alphaG, inC);
    float halo = exp(-max(d, 0.0) * 24.0) * glow * 0.45 * (1.0 - al) * edge_fade(c);
    return float4((c3 * al + col.rgb * halo) * col.a, (al + halo * 0.5) * col.a);
}

// hourglass (28): a wooden frame and two glass bulbs; extra.y is the sand left on top (0…1)
float4 draw_hourglass(float2 c, float phase, float glow, float4 col, float level) {
    float2 p = c * float2(0.55, 0.9);
    float plates = min(sd_box(p - float2(0.0, 0.8), float2(0.46, 0.06), 0.03), sd_box(p - float2(0.0, -0.8), float2(0.46, 0.06), 0.03));
    float posts = min(sd_seg(p, float2(-0.4, -0.78), float2(-0.4, 0.78)), sd_seg(p, float2(0.4, -0.78), float2(0.4, 0.78))) - 0.03;
    float wood = min(plates, posts);
    float ay = abs(p.y);
    float hw = 0.045 + 0.28 * smoothstep(0.04, 0.5, ay) * (1.0 - smoothstep(0.62, 0.74, ay) * 0.4);
    float glass = max(abs(p.x) - hw, ay - 0.74);
    float lv = clamp(level, 0.0, 1.0);
    float topSand = step(0.04, p.y) * step(p.y, 0.06 + 0.6 * lv) * step(glass, 0.0) * step(0.001, lv);
    float pile = 0.06 + 0.58 * (1.0 - lv) - abs(p.x) * 0.35;
    float botSand = step(p.y, -0.74 + pile) * step(p.y, -0.04) * step(glass, 0.0);
    float falling = step(0.001, lv) * step(lv, 0.999) * (1.0 - smoothstep(0.012, 0.025, abs(p.x))) * step(-0.74 + pile, p.y) * step(p.y, 0.06);
    falling *= 0.6 + 0.4 * step(0.5, fract(p.y * 9.0 + phase * 3.0));
    float d = min(wood, glass);
    float aa = fwidth(d) + 1e-4;
    float inW = 1.0 - smoothstep(-aa, aa, wood);
    float inG = 1.0 - smoothstep(-aa, aa, glass);
    float sand = max(max(topSand, botSand), falling);
    float3 sandC = float3(0.98, 0.82, 0.45) * (1.0 + glow * 0.6);
    float3 c3 = float3(0.85, 0.95, 1.0) * 0.25;
    float al = inG * 0.28;
    c3 = mix(c3, sandC, sand); al = max(al, sand);
    c3 = mix(c3, col.rgb * (0.7 + 0.3 * smoothstep(-0.1, 0.1, p.y)), inW); al = max(al, inW);
    float halo = exp(-max(d, 0.0) * 24.0) * glow * 0.45 * (1.0 - al) * edge_fade(c);
    return float4((c3 * al + sandC * halo) * col.a, (al + halo * 0.5) * col.a);
}

// anchor (29): ring, stock, shank and curved arms with flukes, in rusty iron
float4 draw_anchor(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(0.8, 0.95);
    float ring = abs(length(p - float2(0.0, 0.76)) - 0.12) - 0.035;
    float stock = sd_box(p - float2(0.0, 0.52), float2(0.32, 0.04), 0.02);
    float shank = sd_seg(p, float2(0.0, 0.62), float2(0.0, -0.62)) - 0.055;
    float arc = abs(length(p - float2(0.0, -0.2)) - 0.5) - 0.05;
    arc = max(arc, p.y + 0.2);
    float fl = min(sd_tri(p, float2(-0.4, -0.24), float2(-0.62, -0.18), float2(-0.52, 0.04)),
                   sd_tri(p, float2(0.4, -0.24), float2(0.62, -0.18), float2(0.52, 0.04)));
    float d = min(min(ring, stock), min(shank, min(arc, fl)));
    float rust = vnoise(p * 9.0 + 2.0) * vnoise(p * 21.0);
    float3 c3 = mix(col.rgb, float3(0.45, 0.25, 0.12), smoothstep(0.2, 0.5, rust) * 0.7);
    c3 *= 0.75 + 0.35 * smoothstep(-0.6, 0.8, p.y);
    return presence_out(d, c3, glow, float3(1.0, 0.85, 0.5), col.a, c);
}

// flag (30): a pole stuck in the sand and a waving cloth in `col`
float4 draw_flag(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(0.8, 1.1);
    float pole = sd_seg(p, float2(-0.55, -1.05), float2(-0.55, 0.98)) - 0.03;
    float knob = length(p - float2(-0.55, 1.0)) - 0.055;
    // the cloth: two waves running along it (bigger toward the free end), the free end trailing a little lower
    float k = clamp((p.x + 0.52) / 1.12, 0.0, 1.0);
    float w1 = p.x * 5.5 - phase * 4.0, w2 = p.x * 9.0 - phase * 5.3 + 1.0;
    float wave = (sin(w1) * 0.07 + sin(w2) * 0.025) * k - k * k * 0.06;
    float2 q = float2(p.x, p.y - wave);
    float cloth = sd_box(q - float2(0.04, 0.66), float2(0.56, 0.28 - 0.03 * k), 0.02);
    cloth = max(cloth, q.x - 0.58 - sin(q.y * 14.0 + phase * 3.0) * 0.02 * k);   // a fluttering free edge
    float d = min(min(pole, knob), cloth);
    float aa = fwidth(d) + 1e-4;
    float inC = 1.0 - smoothstep(-aa, aa, cloth);
    // folds: lit where the cloth faces up toward the light, in shade in the troughs, with a sheen on the crests
    float slope = (cos(w1) * 0.07 * 5.5 + cos(w2) * 0.025 * 9.0) * k;
    float shade = 0.78 + 0.5 * clamp(-slope * 1.4, -0.6, 0.6);
    float3 cl = col.rgb * shade + float3(1.0) * pow(clamp(-slope, 0.0, 1.0), 3.0) * 0.25;
    cl *= 0.85 + 0.15 * smoothstep(0.38, 0.94, q.y);                         // a little lighter at the top
    float hem = (1.0 - smoothstep(0.0, 0.025, abs(abs(q.y - 0.66 + 0.0) - (0.25 - 0.03 * k)))) * step(abs(q.x - 0.04), 0.56);
    cl *= 1.0 - hem * 0.18;                                                  // hems along the edges
    cl *= 0.7 + 0.3 * smoothstep(-0.55, -0.4, p.x);                         // the pole's shadow on the cloth
    // the pole: a metal rod, lit on one side
    float px = clamp((p.x + 0.55) / 0.03, -1.0, 1.0);
    float3 poleC = float3(0.62, 0.6, 0.55) * (0.55 + 0.5 * sqrt(max(0.0, 1.0 - px * px)) + 0.25 * -px);
    float3 c3 = mix(poleC, cl, inC);
    if (knob < 0.0) {
        float2 kn = (p - float2(-0.55, 1.0)) / 0.055;
        c3 = float3(0.85, 0.72, 0.36) * (0.5 + 0.6 * sqrt(max(0.0, 1.0 - dot(kn, kn)))) + 0.5 * exp(-dot(kn - float2(-0.35, 0.4), kn - float2(-0.35, 0.4)) * 8.0);
    }
    return presence_out(d, c3, glow, col.rgb, col.a, c);
}

// helm (31): a ship's wheel in wood, eight spokes ending in handles, an inner ring and a hub in the state's color;
// `phase` is its turn (radians)
float4 draw_helm(float2 c, float phase, float glow, float4 col, float3 hub) {
    // col.a above 1.5: a rusted iron helm (the deep sea's), its alpha is what's left
    float rust = step(1.5, col.a);
    col.a -= rust * 2.0;
    float2 p = c * 1.05;
    float ca = cos(phase), sa = sin(phase);
    p = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
    float r = length(p);
    float rim = abs(r - 0.6) - 0.065;
    float inner = abs(r - 0.24) - 0.04;
    float hubD = r - 0.15;
    float ang = atan2(p.y, p.x);
    float sector = 3.14159265 / 4.0;
    float a0 = floor(ang / sector + 0.5) * sector;                     // the nearest of the 8 spokes
    float2 q = float2(p.x * cos(-a0) - p.y * sin(-a0), p.x * sin(-a0) + p.y * cos(-a0));
    float spoke = max(abs(q.y) - 0.035, max(0.15 - q.x, q.x - 0.68));
    float handle = sd_seg(q, float2(0.7, 0.0), float2(0.95, 0.0)) - mix(0.05, 0.07, smoothstep(0.72, 0.9, q.x));
    float wood = min(min(rim, inner), min(spoke, handle));
    wood += rust * (vnoise(p * 28.0) - 0.45) * 0.03;                    // rust eats the edges
    float d = min(wood, hubD);
    float aa = fwidth(d) + 1e-4;
    float inW = 1.0 - smoothstep(-aa, aa, wood);
    float inH = 1.0 - smoothstep(-aa, aa, hubD);
    float grain = 0.85 + 0.15 * sin(q.x * 40.0 + vnoise(q * 6.0) * 4.0);
    float3 woodC = col.rgb * grain * (0.75 + 0.35 * smoothstep(-0.8, 0.8, c.y));
    if (rust > 0.5) {
        // dark iron under blotches of orange rust, pitted, with pale flakes
        float blot = smoothstep(0.35, 0.7, vnoise(p * 7.0) * 0.7 + vnoise(p * 19.0) * 0.3);
        float3 iron = float3(0.2, 0.16, 0.14), orange = float3(0.62, 0.3, 0.12);
        woodC = mix(iron, orange, blot) * (0.75 + 0.35 * smoothstep(-0.8, 0.8, c.y)) * (0.8 + 0.4 * vnoise(p * 40.0));
        woodC = mix(woodC, float3(0.75, 0.55, 0.38), step(0.86, vnoise(p * 34.0 + 3.0)) * 0.6);
        woodC *= dot(col.rgb, float3(0.33)) / 0.4;                        // the scene's light (col is the helm's color, lit)
    }
    float3 hubC = hub * (0.8 + 0.4 * (1.0 - r / 0.15)) + float3(0.25) * (1.0 - smoothstep(0.0, 0.07, length(p - float2(-0.04, 0.05))));
    float3 c3 = woodC * inW + hubC * inH;
    float inside = max(inW, inH);
    float halo = exp(-max(d, 0.0) * 24.0) * glow * 0.45 * (1.0 - inside) * edge_fade(c);
    float hubGlow = exp(-max(hubD, 0.0) * 12.0) * 0.35 * (1.0 - inside) * edge_fade(c);
    return float4((c3 * inside + col.rgb * halo + hub * hubGlow) * col.a, (inside + halo * 0.5 + hubGlow * 0.4) * col.a);
}

float4 draw_presence(int kind, float2 c, float phase, float glow, float4 col, float4 extra) {
    switch (kind) {
        case 25: return draw_shark(c, phase, glow, col, extra.z);   // extra.z: 1 is the hammerhead
        case 26: return draw_submarine(c, phase, glow, col);
        case 27: return draw_bottle(c, phase, glow, col, extra.z);  // extra.z: 1 is the deep sea's
        case 28: return draw_hourglass(c, phase, glow, col, extra.y);
        case 29: return draw_anchor(c, phase, glow, col);
        case 31: return draw_helm(c, phase, glow, col, extra.yzw);
        default: return draw_flag(c, phase, glow, col);
    }
}

// Frost on the glass (a theme's "frost"): over the whole window, ice growing in from the sides and the corners in
// feathery crystals, thicker at the very edge, breathing a little. c: -1…1 over the window, amount 0…1, aspect w/h.
// anglerfish (deep sea): a round dark body with a huge toothy mouth and a glowing lure dangling in front of it.
// phase: time; open (0…1): how wide the mouth is; col: the body's color.
float4 draw_anglerfish(float2 c, float phase, float open, float4 col) {
    float2 p = c * float2(1.3, 1.0);
    float sway = sin(phase * 1.3) * 0.04;
    p.y -= sway * smoothstep(0.0, -1.2, p.x);                                     // the tail sways
    float body = (length((p - float2(0.1, -0.05)) / float2(0.72, 0.56)) - 1.0) * 0.4;
    float jaw = (length((p - float2(0.48, -0.32 - open * 0.12)) / float2(0.5, 0.2)) - 1.0) * 0.15;   // the underbite
    body = smin_k(body, jaw, 0.08);
    float tail = sd_tri(p, float2(-0.45, 0.18), float2(-0.45, -0.24), float2(-1.0, -0.02)) - 0.04;
    float2 tp = p - float2(-0.95, -0.02);
    float fin = sd_tri(tp, float2(0.05, 0.0), float2(-0.3, 0.28 + sway), float2(-0.3, -0.26 + sway)) - 0.03;
    float dorsal = sd_tri(p, float2(-0.1, 0.42), float2(-0.45, 0.4), float2(-0.3, 0.6)) - 0.02;
    float d = min(min(body, smin_k(tail, fin, 0.05)), dorsal);
    // the mouth: a wedge cut into the front, gaping as it opens
    float2 m0 = float2(0.18, -0.1), mu = float2(0.95, 0.02 + open * 0.12), ml = float2(0.98, -0.2 - open * 0.3);
    float mouth = sd_tri(p, m0, mu, ml);
    float inMouth = (1.0 - smoothstep(-0.01, 0.01, mouth)) * step(d, 0.0);
    // teeth: thin needles along both jaws, pointing into the mouth
    float teeth = 0.0;
    for (int j = 0; j < 2; j++) {
        float2 a = m0 + (j == 0 ? float2(0.15, 0.03) : float2(0.15, -0.04)), b = j == 0 ? mu : ml;
        float2 ab = b - a; float h = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
        float2 n = normalize(float2(-ab.y, ab.x)) * (j == 0 ? -1.0 : 1.0);
        float into = dot(p - (a + ab * h), n);
        float saw = 1.0 - abs(fract(h * 7.0) * 2.0 - 1.0);
        teeth = max(teeth, step(0.0, into) * (1.0 - smoothstep(saw * (0.05 + 0.04 * h) - 0.01, saw * (0.05 + 0.04 * h), into)));
    }
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // rough dark skin, lighter where the lure lights it, a pale little eye
    float3 c3 = col.rgb * (0.7 + 0.5 * vnoise(p * 9.0)) * (0.8 + 0.4 * smoothstep(-0.5, 0.4, p.y));
    c3 *= 1.0 - 0.35 * step(0.82, vnoise(p * 26.0));
    // the lure: a stalk arching up from the forehead, a bulb swinging at its tip, pulsing
    float2 base = float2(0.35, 0.42), mid = float2(0.62, 0.92), tip = float2(0.9 + sin(phase * 0.9) * 0.05, 0.66 + sin(phase * 1.4) * 0.04);
    float stalk = min(sd_seg(p, base, mid), sd_seg(p, mid, tip)) - 0.012;
    float pulse = 0.75 + 0.25 * sin(phase * 2.2) * sin(phase * 0.7 + 1.0);
    float bulbR = length(p - tip);
    float bulb = 1.0 - smoothstep(0.045, 0.06, bulbR);
    float3 lureCol = float3(0.55, 1.0, 0.85);
    float lit = exp(-dot(p - tip, p - tip) * 3.0) * pulse;
    c3 += lureCol * lit * 0.35 * a;
    c3 = mix(c3, float3(0.07, 0.01, 0.02), inMouth);
    c3 = mix(c3, float3(0.85, 0.85, 0.78) * (0.5 + 0.6 * lit), teeth * inMouth);
    float eye = 1.0 - smoothstep(0.03, 0.045, length(p - float2(0.4, 0.18)));
    c3 = mix(c3, float3(0.75, 0.8, 0.7) * (0.6 + 0.6 * lit), eye);
    float sa = 1.0 - smoothstep(-0.006, 0.006, stalk);
    float3 rgb = c3 * a;
    float alpha = a;
    rgb = mix(rgb, col.rgb * 1.4 + lureCol * lit * 0.2, sa * (1.0 - a)); alpha = max(alpha, sa);
    rgb = mix(rgb, lureCol * (0.8 + 0.6 * pulse), bulb); alpha = max(alpha, bulb);
    float halo = exp(-bulbR * bulbR * 18.0) * pulse * 0.75 * (1.0 - bulb) * (1.0 - smoothstep(0.8, 1.0, abs(c.y))) * (1.0 - smoothstep(0.85, 1.0, abs(c.x)));
    rgb += lureCol * halo; alpha = max(alpha, halo * 0.4);
    return float4(rgb, alpha);
}

// ocean sunfish (mola): a huge flat pale disc that seems to have no tail, with a tall fin above and one below
// sculling together, and a scalloped rim behind. phase: time.
float4 draw_sunfish(float2 c, float phase, float4 col) {
    float2 p = c * float2(1.0, 1.25);
    float scull = sin(phase * 0.9) * 0.14;
    float body = (length((p - float2(0.05, 0.0)) / float2(0.66, 0.52)) - 1.0) * 0.4;
    // the clavus: the rim that replaces a tail, scalloped
    float rim = -0.62 - 0.035 * (0.5 + 0.5 * cos(p.y * 22.0));
    float clavus = max(rim - p.x, max(p.x + 0.45, abs(p.y) - 0.42 + 0.25 * smoothstep(-0.45, -0.7, p.x)));
    body = max(body, -0.66 - p.x);
    body = smin_k(body, clavus, 0.06);
    float top = sd_tri(p, float2(-0.08, 0.4), float2(-0.42, 0.4), float2(-0.3 + scull, 1.2)) - 0.04;
    float bot = sd_tri(p, float2(-0.08, -0.4), float2(-0.42, -0.4), float2(-0.3 - scull, -1.2)) - 0.04;
    float pect = (length((p - float2(0.22, 0.0)) / float2(0.1, 0.05 + 0.02 * sin(phase * 2.0))) - 1.0) * 0.05;
    float d = smin_k(smin_k(body, top, 0.05), bot, 0.05);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa * 1.5, d);
    float inBody = 1.0 - smoothstep(-0.01, 0.01, body);
    // round: the disc bulges, lit from above and a little in front, the edges falling into shadow
    float2 bq = (p - float2(0.05, 0.0)) / float2(0.66, 0.52);
    float bulge = sqrt(max(0.0, 1.0 - min(1.0, dot(bq, bq))));
    float3 nrm = normalize(float3(bq * 0.9, bulge + 0.2));
    float diff = 0.35 + 0.75 * max(0.0, dot(nrm, normalize(float3(0.25, 0.7, 0.65))));
    // silvery skin: darker back, pale belly, mottled with soft grey patches and fine sandpaper grain
    float3 c3 = col.rgb * mix(0.7, 1.25, smoothstep(0.45, -0.5, p.y));
    float blot = smoothstep(0.45, 0.75, vnoise(p * 4.5 + 2.0));
    c3 = mix(c3, c3 * 0.72, blot * 0.6);
    c3 *= 0.9 + 0.2 * vnoise(p * 55.0);
    c3 = mix(c3, c3 * 1.15 + 0.03, step(0.8, vnoise(p * 22.0 + 7.0)) * 0.5);          // pale freckles
    c3 *= mix(1.0, diff, inBody);
    // the fins: darker, with rays running along them, a pale trailing edge
    float finM = (1.0 - inBody) * step(abs(p.y), 1.3);
    float fy = abs(p.y);
    float rays = 0.85 + 0.15 * sin((p.x + 0.3 + (p.y > 0.0 ? -scull : scull) * fy) * 70.0);
    c3 = mix(c3, col.rgb * 0.55 * rays * (0.8 + 0.4 * smoothstep(1.1, 0.4, fy)), finM * step(0.36, fy));
    // the clavus: wrinkled with ridges ending in the scallops
    float clav = smoothstep(-0.5, -0.6, p.x) * inBody;
    c3 = mix(c3, c3 * (0.72 + 0.18 * sin(p.y * 22.0)), clav);
    // the pectoral fin, a gill slit before it
    c3 = mix(c3, c3 * 0.7, 1.0 - smoothstep(0.0, 0.01, pect));
    c3 *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.012, abs(length(p - float2(0.4, 0.0)) - 0.12))) * step(abs(p.y), 0.07) * step(p.x, 0.3);
    // a rim of light along the back, a small round mouth, a big dark eye with a pale ring and a glint
    c3 += col.rgb * 0.3 * (1.0 - smoothstep(0.0, 0.05, -d)) * smoothstep(-0.2, 0.4, p.y);
    float mouthD = length(p - float2(0.68, -0.02));
    c3 *= 1.0 - 0.6 * (1.0 - smoothstep(0.03, 0.045, mouthD));
    float er = length(p - float2(0.43, 0.12));
    c3 = mix(c3, col.rgb * 1.3, 1.0 - smoothstep(0.06, 0.075, er));
    c3 = mix(c3, float3(0.04, 0.05, 0.07), 1.0 - smoothstep(0.035, 0.05, er));
    c3 = mix(c3, float3(0.85), 1.0 - smoothstep(0.006, 0.012, length(p - float2(0.445, 0.135))));
    float aw = a * 0.88;
    return float4(c3 * aw, aw);
}

float4 draw_frost(float2 c, float t, float amount, float aspect) {
    float2 px = float2(c.x * aspect, c.y);
    // patches growing in from the left and right sides, longer at the corners, absent in some stretches
    float side = (1.0 - abs(c.x)) * aspect;
    float corner = smoothstep(0.35, 1.0, abs(c.y));
    float patchy = smoothstep(0.3, 0.75, vnoise(float2(c.y * 3.0 + sign(c.x) * 5.0, 1.7)));
    float reach = amount * (0.04 + 0.16 * patchy + 0.14 * corner) * (1.0 + 0.05 * sin(t * 0.25));
    // the frost's edge is ragged: noise pushes it in and out
    float edgeD = side - reach * (0.75 + 0.5 * vnoise(px * 10.0));
    float grow = 1.0 - smoothstep(-0.01, 0.03, edgeD);
    // and a little along the top and bottom near the corners
    float tb = (1.0 - abs(c.y)) - amount * 0.06 * corner * smoothstep(0.6, 1.0, abs(c.x)) * (0.6 + 0.8 * vnoise(px * 9.0));
    grow = max(grow, 1.0 - smoothstep(-0.01, 0.03, tb));
    if (grow <= 0.001) return float4(0.0);
    // inside it: a milky haze, fine crystal grains, and feathery needles pointing inward
    float haze = 0.45 + 0.4 * vnoise(px * 22.0);
    float grains = smoothstep(0.75, 0.95, vnoise(px * 60.0));
    float2 dir = normalize(float2(-sign(c.x), 0.3 * (vnoise(px * 4.0) - 0.5)));
    float needle = abs(sin(dot(px, float2(dir.y, -dir.x)) * 160.0 + vnoise(px * 8.0) * 5.0));
    float feathers = (1.0 - smoothstep(0.0, 0.18, needle)) * smoothstep(0.02, -0.03, edgeD) * 0.5;
    float rim = (1.0 - smoothstep(0.0, 0.025, abs(edgeD))) * 0.35;               // the growing edge is brighter
    float a = grow * (haze * 0.35 + grains * 0.3 + feathers + rim);
    float3 col = mix(float3(0.78, 0.9, 1.0), float3(1.0), grains + feathers + rim);
    return float4(col * a, a * 0.8);
}

// a background that didn't compile is replaced by this one (nothing): the theme keeps the usual background
float4 fishbots_no_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) { return float4(0.0); }

"""#
