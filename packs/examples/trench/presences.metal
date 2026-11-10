// The trench's own look for the built-in pieces: the bathysphere (chest), the glass float (bottle), the helm grown
// over with living light, the expedition's beacon (flag).

// A bathysphere in place of the chest: a riveted steel ball that came down on a cable and never went back up, on
// its skid in the mud, the cable's end still on its lifting eye. Its round hatch swings open (extra.y) on what it
// was carrying, and the light pours out. The ground at y ≈ -0.9.
float4 draw_trench_bathysphere(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float open = clamp(extra.y, 0.0, 1.0);
    float lum = dot(col.rgb, float3(0.3333));
    float2 sc = p - float2(0.0, -0.2);
    float r = length(sc);
    float sphere = r - 0.6;
    float skid = sd_box(p - float2(0.0, -0.87), float2(0.52, 0.035), 0.02);
    float legs = min(sd_seg(p, float2(-0.3, -0.68), float2(-0.42, -0.85)), sd_seg(p, float2(0.3, -0.68), float2(0.42, -0.85))) - 0.04;
    float lug = abs(length(p - float2(0.0, 0.45)) - 0.07) - 0.028;
    // the cable: a few links of it, slack, drifting
    float sway = sin(t * 0.5) * 0.04;
    float cable = min(sd_seg(p, float2(0.0, 0.52), float2(0.1 + sway, 0.7)),
                      sd_seg(p, float2(0.1 + sway, 0.7), float2(0.02 + sway * 2.0, 0.9))) - 0.016;
    float frame = min(min(skid, legs), min(lug, cable));
    // the hatch: a hole, its ring, and the door swinging on a hinge at the left
    float2 hc = float2(0.04, -0.2);
    float hole = length(p - hc) - 0.27;
    float ring = abs(length(p - hc) - 0.3) - 0.04;
    float ang = open * 2.0;
    float hx = hc.x - 0.3;
    float2 dq = p - float2(hx + 0.3 * cos(ang), hc.y);
    float door = (length(dq / float2(0.3 * abs(cos(ang)) + 0.025, 0.3)) - 1.0) * 0.3;
    float d = min(min(sphere, frame), door);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 gold = float3(1.0, 0.76, 0.32);
    float3 c3 = float3(0.0);
    if (a > 0.001) {
        // steel: round, lit from above, rusting from the seams
        float3 n = normalize(float3(sc / 0.6, sqrt(max(0.02, 1.0 - dot(sc, sc) / 0.36))));
        float lt = 0.3 + 0.8 * max(0.0, dot(n, normalize(float3(-0.3, 0.8, 0.5))));
        float3 steel = float3(0.42, 0.47, 0.52) * lt;
        float rust = smoothstep(0.45, 0.75, vnoise(p * 7.0 + 3.0) * 0.7 + vnoise(p * 22.0) * 0.3 + 0.2 * smoothstep(0.1, -0.6, p.y));
        steel = mix(steel, float3(0.5, 0.26, 0.12) * lt, rust * 0.75);
        steel += float3(0.7, 0.8, 0.9) * pow(max(0.0, dot(n, normalize(float3(-0.35, 0.7, 0.6)))), 22.0) * 0.5;
        steel *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.012, abs(abs(sc.y - 0.02) - 0.33)));        // two seams around it
        c3 = steel;
        if (frame < sphere) c3 = float3(0.26, 0.28, 0.32) * (0.7 + 0.5 * smoothstep(-0.9, 0.9, p.y));
        // the ring, with its bolts
        float ra = atan2(p.y - hc.y, p.x - hc.x);
        float bolt = 1.0 - smoothstep(0.012, 0.022, length(float2(fract(ra * 12.0 / 6.28318) - 0.5, (length(p - hc) - 0.3) * 6.0)) * 0.16);
        if (ring < 0.0) c3 = mix(float3(0.3, 0.33, 0.37) * (0.6 + 0.7 * lt), float3(0.6, 0.63, 0.66) * lt, bolt);
        // inside the hole: what it carried, shining
        if (hole < 0.0) {
            float2 g = (p - hc) * 22.0;
            float hs = hash21(floor(g));
            float twinkle = step(0.6, hs) * (1.0 - smoothstep(0.1, 0.4, length(fract(g) - 0.5))) * (0.5 + 0.5 * sin(t * (2.0 + hs * 3.0) + hs * 40.0));
            float heap = smoothstep(0.02, -0.12, p.y - hc.y + 0.05 * sin(p.x * 14.0));
            float3 inner = gold * (0.25 + 0.55 * heap) * (0.6 + 0.4 * glow) + float3(1.0, 0.95, 0.7) * twinkle * heap * 0.8;
            inner *= 1.0 - 0.6 * smoothstep(-0.12, 0.0, hole);
            c3 = mix(float3(0.01, 0.015, 0.03), inner, smoothstep(0.02, 0.25, open));
        }
        // the door: the same steel, a little thick glass eye in it, a wheel to lock it
        if (door < 0.0) {
            float turn = abs(cos(ang)) + 0.08;
            float3 dc = mix(float3(0.36, 0.4, 0.45), float3(0.5, 0.26, 0.12), rust * 0.5) * (0.5 + 0.6 * lt) * (0.6 + 0.4 * turn);
            float2 eq = float2(dq.x / turn, dq.y);
            float er = length(eq);
            dc = mix(dc, float3(0.6, 0.63, 0.66) * lt, 1.0 - smoothstep(0.0, 0.012, abs(er - 0.15) - 0.02));
            float3 glass = mix(float3(0.03, 0.06, 0.1), gold * 0.5, 0.25 + 0.2 * sin(t * 0.7)) + float3(0.6, 0.8, 1.0) * (1.0 - smoothstep(0.0, 0.05, length(eq - float2(-0.05, 0.06)))) * 0.35;
            dc = mix(dc, glass, 1.0 - smoothstep(0.12, 0.135, er));
            dc *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.02, -door));
            c3 = dc;
        }
        c3 *= lum * 1.6;
        if (hole < 0.0 && door >= 0.0) c3 /= max(0.2, lum * 1.6);            // the treasure's own light doesn't dim with the hour
        c3 *= 0.55 + 0.45 * smoothstep(-0.92, -0.7, p.y);
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.25;
    }
    float edge = 1.0 - smoothstep(0.65, 1.0, max(abs(c.x), abs(c.y)));
    float2 hq = p - hc;
    float halo = (exp(-dot(hq, hq) * 6.0) * 0.5 + exp(-dot(hq, hq) * 30.0) * 0.4) * open * (0.5 + 0.5 * glow) * edge * step(-0.9, p.y);
    c3 += gold * halo * (hole < 0.0 ? 0.0 : 0.6);
    return float4(c3 * a + gold * halo * (1.0 - a), a + halo * 0.5 * (1.0 - a));
}

// A helm grown over, in place of the helm: black iron eaten thin, a hub alive with light in the state's color
// (col), and little anemones along the rim that glow the same color. phase: how far it has turned.
float4 draw_trench_helm(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * 1.05;
    float ca = cos(phase), sa = sin(phase);
    float2 q = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
    float r = length(q);
    float rim = abs(r - 0.6) - 0.055 - 0.012 * vnoise(q * 12.0);
    float hubD = r - 0.16;
    float ang = atan2(q.y, q.x);
    float sector = 3.14159265 / 4.0;
    float a0 = floor(ang / sector + 0.5) * sector;
    float2 s = float2(q.x * cos(-a0) - q.y * sin(-a0), q.x * sin(-a0) + q.y * cos(-a0));
    float spoke = max(abs(s.y) - 0.032, max(0.15 - s.x, s.x - 0.68));
    float handle = sd_seg(s, float2(0.7, 0.0), float2(0.9, 0.0)) - 0.05;
    float iron = min(min(rim, spoke), handle);
    float d = min(iron, hubD);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    float pulse = 0.75 + 0.25 * sin(phase * 3.0 + r * 6.0);
    float3 c3 = float3(0.1, 0.115, 0.14) * (0.6 + 0.6 * vnoise(q * 16.0)) * (0.6 + 0.6 * smoothstep(-0.8, 0.8, c.y));
    c3 = mix(c3, float3(0.3, 0.17, 0.09), 0.5 * smoothstep(0.5, 0.8, vnoise(q * 7.0 + 5.0)));
    c3 += hue * exp(-r * 3.2) * 0.45;                                        // the hub's light on the spokes
    // anemones on the rim: little rosettes, lit
    float2 g = float2(ang * 14.0 / 6.28318, (r - 0.6) * 9.0);
    float hs = hash21(floor(float2(g.x, 0.0)) + 11.0);
    float an = (1.0 - smoothstep(0.15, 0.42, length(float2(fract(g.x) - 0.5, g.y - (hs - 0.5) * 0.5)))) * step(0.35, hs) * step(rim, 0.0);
    c3 = mix(c3, hue * (0.7 + 0.5 * glow) * pulse + float3(0.25), an * 0.9);
    if (hubD < 0.0) {
        float3 n = normalize(float3(q / 0.16, sqrt(max(0.02, 1.0 - r * r / 0.0256))));
        c3 = hue * (0.55 + 0.6 * n.z) * (0.8 + 0.4 * glow) * pulse + float3(1.0) * pow(n.z, 6.0) * 0.35;
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;
    float edge = 1.0 - smoothstep(0.7, 1.0, length(c));
    float halo = (exp(-max(hubD, 0.0) * 9.0) * 0.4 + exp(-abs(r - 0.6) * 14.0) * 0.12) * (0.7 + 0.5 * glow) * (1.0 - a) * edge;
    return float4((c3 * a + hue * halo) * col.a, (a + halo * 0.45) * col.a);
}

// A glass float in place of the bottle: a hand-blown glass ball in its rope net, lost from a net a long way up,
// a light inside it in the state's color (col), a frayed line hanging under it with a brass tag.
float4 draw_trench_float(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    p.x -= sin(phase * 0.8) * 0.02;
    float2 bc = float2(0.0, 0.22);
    float2 bq = p - bc;
    float r = length(bq);
    float ball = r - 0.4;
    // the line under it, swaying, and the tag at its end
    float ly = clamp(p.y, -0.72, -0.16);
    float lx = sin(ly * 6.0 + phase * 1.1) * 0.05 * smoothstep(-0.16, -0.7, ly);
    float line = length(p - float2(lx, ly)) - 0.012;
    float2 tq = p - float2(sin(-0.72 * 6.0 + phase * 1.1) * 0.05, -0.78);
    float tag = sd_box(tq, float2(0.05, 0.06), 0.015);
    float d = min(min(ball, line), tag);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    float lit = (0.65 + 0.35 * sin(phase * 1.7)) * (0.75 + 0.5 * glow);
    float3 c3;
    float alpha = a;
    if (ball <= min(line, tag)) {
        // glass: thick at the rim, the light inside, a window's reflection
        float rimK = smoothstep(0.22, 0.4, r);
        c3 = float3(0.3, 0.6, 0.55) * (0.15 + 0.85 * rimK * rimK);
        c3 += hue * (exp(-r * r * 60.0) * 1.3 + exp(-r * r * 12.0) * 0.35) * lit + float3(1.0) * exp(-r * r * 140.0) * lit;
        c3 += float3(0.8, 0.95, 1.0) * (1.0 - smoothstep(0.0, 0.07, length((bq - float2(-0.15, 0.17)) / float2(1.0, 1.6)))) * 0.45;
        // the net: knotted rope in diamonds, gathered into a ring at the bottom
        float z = sqrt(max(0.0, 0.16 - r * r));
        float2 nq = float2(atan2(bq.x, z), asin(clamp(bq.y / 0.4, -1.0, 1.0))) * 1.15;
        float net = min(abs(fract(nq.x + nq.y) - 0.5), abs(fract(nq.x - nq.y) - 0.5));
        float rope = 1.0 - smoothstep(0.02, 0.05, net);
        c3 = mix(c3, float3(0.42, 0.34, 0.2) * (0.45 + 0.4 * rimK) + hue * 0.2 * lit * exp(-r * 4.0), rope * 0.9);
        alpha = a * max(0.55 + 0.4 * rimK, rope);
    } else if (tag < line) {
        c3 = float3(0.6, 0.48, 0.2) * (0.6 + 0.5 * smoothstep(-0.06, 0.06, tq.y)) + hue * 0.15 * lit;
    } else {
        c3 = float3(0.33, 0.28, 0.2);
    }
    float edge = 1.0 - smoothstep(0.65, 1.0, max(abs(c.x), abs(c.y)));
    float halo = (exp(-max(ball, 0.0) * 9.0) * 0.45) * lit * (1.0 - a) * edge;
    return float4((c3 * alpha + hue * halo) * col.a, (alpha + halo * 0.45) * col.a);
}

// The expedition's beacon in place of the flag: a tripod someone lowered to mark the spot, an instrument box, a
// mast with a pennant in the state's color (col) and a lamp on top that still blinks it. The ground at y ≈ -0.9.
float4 draw_trench_beacon(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.8, 1.0);
    float2 hubP = float2(0.0, -0.32);
    float legs = min(min(sd_seg(p, hubP, float2(-0.36, -0.9)), sd_seg(p, hubP, float2(0.36, -0.9))), sd_seg(p, hubP, float2(0.06, -0.9))) - 0.022;
    float feet = min(sd_box(p - float2(-0.36, -0.9), float2(0.07, 0.02), 0.01), sd_box(p - float2(0.36, -0.9), float2(0.07, 0.02), 0.01));
    float box = sd_box(p - hubP, float2(0.13, 0.1), 0.03);
    float mast = sd_box(p - float2(0.0, 0.17), float2(0.016, 0.42), 0.005);
    float2 lp = p - float2(0.0, 0.66);
    float lamp = length(lp) - 0.075;
    float cage = sd_box(p - float2(0.0, 0.575), float2(0.06, 0.02), 0.008);
    // the pennant: a long triangle, waving
    float k = clamp(p.x / 0.5, 0.0, 1.0);
    float2 fq = float2(p.x, p.y - sin(p.x * 9.0 - phase * 3.0) * 0.05 * k);
    float pennant = sd_tri(fq, float2(0.015, 0.5), float2(0.015, 0.26), float2(0.52, 0.36));
    float metal = min(min(legs, feet), min(min(box, mast), cage));
    float d = min(min(metal, lamp), pennant);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 hue = col.rgb / max(0.05, max(col.r, max(col.g, col.b)));
    float blink = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(phase * 2.2), 6.0);
    float lit = blink * (0.8 + 0.5 * glow);
    float3 c3;
    if (lamp <= min(metal, pennant)) {
        c3 = hue * (0.5 + 1.0 * lit) + float3(1.0) * exp(-dot(lp, lp) * 500.0) * lit;
    } else if (pennant < metal) {
        c3 = hue * (0.75 + 0.2 * cos(p.x * 9.0 - phase * 3.0) * k) * (0.8 + 0.5 * lit * smoothstep(0.5, 0.0, length(lp)));
        c3 = mix(c3, c3 * 0.6, step(0.5, fract(fq.x * 6.0)) * 0.25);
    } else {
        c3 = float3(0.3, 0.32, 0.36) * (0.55 + 0.6 * smoothstep(-0.9, 0.6, p.y));
        c3 = mix(c3, float3(0.75, 0.6, 0.15), step(box, 0.0) * 0.6);                        // the yellow instrument box
        c3 = mix(c3, float3(0.05), step(box, 0.0) * (1.0 - smoothstep(0.03, 0.04, length(p - hubP - float2(0.04, 0.0)))));
        c3 += hue * lit * exp(-length(lp) * 4.0) * 0.5;                                      // the lamp's light on the frame
    }
    c3 *= 0.6 + 0.4 * smoothstep(-0.92, -0.75, p.y);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = (exp(-dot(lp, lp) * 60.0) * 0.7 + exp(-dot(lp, lp) * 9.0) * 0.25) * lit * (1.0 - a) * edge;
    return float4((c3 * a + hue * halo) * col.a, (a + halo * 0.5) * col.a);
}

// A goblin shark in place of the shark: a long flabby body the color of raw flesh, a flat blade of a snout far out
// over its jaws, a small eye, a long low tail. p = c * (1.8, 0.7), facing +x.
float4 draw_trench_goblin(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.8, 0.7);
    p.y -= sin(phase * 1.1 - p.x * 1.8) * 0.06 * smoothstep(0.3, -1.6, p.x);
    float thin = mix(0.28, 1.0, smoothstep(-1.35, 0.1, p.x));
    float body = (length((p - float2(-0.15, 0.0)) / float2(1.2, 0.21 * thin)) - 1.0) * 0.21;
    float snout = sd_tri(p, float2(0.8, 0.15), float2(1.68, 0.11), float2(0.85, 0.02)) - 0.015;
    float jaw = (length((p - float2(0.98, -0.1)) / float2(0.2, 0.065)) - 1.0) * 0.065;
    float head = smin_k(smin_k(body, snout, 0.06), jaw, 0.04);
    float dors = max((length((p - float2(0.05, 0.16)) / float2(0.2, 0.13)) - 1.0) * 0.13, 0.14 - p.y);
    float dors2 = max((length((p - float2(-0.7, 0.1)) / float2(0.15, 0.09)) - 1.0) * 0.09, 0.08 - p.y);
    float pect = (length(float2((p.x - 0.42) * 0.8 + (p.y + 0.2) * 0.6, -(p.x - 0.42) * 0.6 + (p.y + 0.2) * 0.8) / float2(0.24, 0.07)) - 1.0) * 0.07;
    float pelv = max((length((p - float2(-0.45, -0.15)) / float2(0.18, 0.09)) - 1.0) * 0.09, p.y + 0.12);
    float2 tq = p - float2(-1.28, 0.0);
    float tail = min(sd_tri(tq, float2(0.12, 0.05), float2(-0.48, 0.2), float2(-0.2, -0.04)),
                     sd_tri(tq, float2(0.1, 0.0), float2(-0.16, -0.14), float2(-0.1, 0.0))) - 0.01;
    float fins = min(min(dors, dors2), min(min(pect, pelv), tail));
    float d = min(head, fins);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001 && glow < 0.01) return float4(0.0);
    // soft pink-gray skin, almost see-through, bluer on the fins and the snout's edge
    float3 c3 = col.rgb * (0.6 + 0.6 * smoothstep(-0.2, 0.2, p.y)) * (0.92 + 0.12 * vnoise(p * float2(12.0, 30.0)));
    c3 = mix(c3, col.rgb * float3(0.6, 0.72, 0.95), smoothstep(0.9, 1.6, p.x) * 0.5);
    if (fins < head) c3 = col.rgb * float3(0.5, 0.62, 0.85) * (0.75 + 0.2 * sin(atan2(p.y, p.x + 0.3) * 60.0));
    for (int i = 0; i < 5; i++)                                                // gill slits
        c3 *= 1.0 - 0.3 * (1.0 - smoothstep(0.004, 0.012, abs(p.x - 0.6 + float(i) * 0.045 + p.y * 0.3))) * step(abs(p.y + 0.02), 0.09);
    // the jaws: a dark mouth with needle teeth
    float mouth = sd_seg(p, float2(0.84, -0.09), float2(1.14, -0.085)) - 0.014;
    c3 = mix(c3, float3(0.08, 0.02, 0.03), 1.0 - smoothstep(0.0, 0.01, mouth));
    c3 = mix(c3, float3(0.95), (1.0 - smoothstep(0.0, 0.01, mouth)) * step(0.55, fract(p.x * 26.0)) * 0.9);
    float er = length(p - float2(0.9, 0.04));
    c3 = mix(c3, float3(0.02), 1.0 - smoothstep(0.022, 0.032, er));
    c3 = mix(c3, float3(0.7, 0.9, 1.0), 1.0 - smoothstep(0.004, 0.01, length(p - float2(0.905, 0.05))));
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.22;
    c3 += col.rgb * glow * 0.3;
    float alpha = a * (fins < head ? 0.85 : 1.0);
    float edge = 1.0 - smoothstep(0.75, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 20.0) * glow * 0.45 * (1.0 - a) * edge;
    return float4((c3 * alpha + col.rgb * halo) * col.a, (alpha + halo * 0.5) * col.a);
}

// A sediment clock in place of the hourglass: a sampling tube stood in the mud on three feet, pinched in the
// middle, the living dust it caught still glowing as it falls from the top chamber to the bottom one.
// extra.y: how much is left on top (0…1). p = c * (0.7, 1.0); the ground at y ≈ -0.9.
float4 draw_trench_sedclock(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(0.7, 1.0);
    float v = clamp(extra.y, 0.0, 1.0);
    float waistY = -0.12;
    float w = 0.2 - 0.15 * exp(-pow((p.y - waistY) / 0.09, 2.0));
    float glass = max(abs(p.x) - w, max(p.y - 0.5, -0.72 - p.y));
    float capT = sd_box(p - float2(0.0, 0.55), float2(0.25, 0.05), 0.02);
    float capB = sd_box(p - float2(0.0, -0.76), float2(0.25, 0.045), 0.02);
    float ringT = abs(length(p - float2(0.0, 0.7)) - 0.07) - 0.022;
    float feet = min(sd_seg(p, float2(-0.2, -0.78), float2(-0.34, -0.9)), sd_seg(p, float2(0.2, -0.78), float2(0.34, -0.9))) - 0.025;
    float rods = min(abs(p.x - 0.235), abs(p.x + 0.235)) - 0.012;
    rods = max(rods, max(p.y - 0.55, -0.76 - p.y));
    float metal = min(min(capT, capB), min(min(ringT, feet), rods));
    float d = min(glass, metal);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 hue = mix(col.rgb / max(0.05, max(col.r, max(col.g, col.b))), float3(0.4, 1.0, 0.8), 0.6);
    // the dust: piled on top (sinking in the middle), heaped at the bottom, a thread of it falling
    float topLvl = waistY + 0.06 + 0.5 * v - 0.05 * (1.0 - abs(p.x) / 0.2) * step(0.02, v);
    float botLvl = -0.72 + 0.46 * (1.0 - v) * (1.0 - 0.5 * abs(p.x) / 0.2);
    float inTop = step(waistY, p.y) * (1.0 - smoothstep(topLvl - 0.01, topLvl + 0.01, p.y)) * step(0.005, v);
    float inBot = step(p.y, waistY) * (1.0 - smoothstep(botLvl - 0.01, botLvl + 0.01, p.y));
    float fallK = step(0.01, v) * step(v, 0.995);
    float stream = (1.0 - smoothstep(0.006, 0.02, abs(p.x))) * step(botLvl, p.y) * step(p.y, waistY + 0.05) * fallK
                 * (0.5 + 0.5 * sin(p.y * 60.0 + phase * 9.0));
    float2 g = p * 34.0;
    float hs = hash21(floor(g));
    float grain = 0.55 + 0.45 * hs + step(0.85, hs) * (0.5 + 0.5 * sin(phase * (1.0 + hs * 3.0) + hs * 30.0));
    float dust = max(max(inTop, inBot) * grain, stream);
    float3 c3;
    float alpha = a;
    if (glass <= metal) {
        float rimK = smoothstep(w - 0.06, w, abs(p.x));
        c3 = float3(0.3, 0.5, 0.55) * (0.15 + 0.6 * rimK) + hue * dust * (0.85 + 0.4 * glow);
        c3 += float3(0.8, 0.95, 1.0) * (1.0 - smoothstep(0.0, 0.02, abs(p.x + w * 0.55))) * 0.2;      // a line of reflection
        alpha = a * max(0.4 + 0.5 * rimK, min(1.0, dust));
    } else {
        c3 = float3(0.36, 0.3, 0.2) * (0.6 + 0.5 * smoothstep(-0.9, 0.7, p.y)) * (0.4 + 2.0 * dot(col.rgb, float3(0.33)));
        c3 += hue * 0.12 * smoothstep(0.5, 0.0, abs(p.x));
    }
    c3 *= 0.6 + 0.4 * smoothstep(-0.92, -0.76, p.y);
    float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(glass, 0.0) * 9.0) * (0.22 + 0.3 * glow) * (1.0 - a) * edge * step(-0.85, p.y);
    return float4((c3 * alpha + hue * halo) * col.a, (alpha + halo * 0.4) * col.a);
}

// A power cell in place of the battery: the expedition's yellow instrument case on two skids, a carrying handle,
// a dark window with five bars of charge (extra.y, 0…1): green, amber when low, red and blinking when nearly out;
// while it's busy (charging) the bars run. p = c * (1.0, 0.8); the ground at y ≈ -0.72.
float4 draw_trench_cell(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.8);
    float v = clamp(extra.y, 0.0, 1.0);
    bool busy = abs(extra.w - 1.0) < 0.5;
    float2 bc = float2(0.0, -0.28);
    float box = sd_box(p - bc, float2(0.66, 0.34), 0.07);
    float skids = min(sd_box(p - float2(-0.4, -0.68), float2(0.14, 0.035), 0.02), sd_box(p - float2(0.4, -0.68), float2(0.14, 0.035), 0.02));
    float handle = max(abs(length((p - float2(0.0, 0.06)) / float2(1.0, 0.75)) - 0.26) - 0.03, 0.06 - p.y);
    float d = min(min(box, skids), handle);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float lum = 0.4 + 2.0 * dot(col.rgb, float3(0.3333)) * 0.5;
    float3 c3 = float3(0.86, 0.66, 0.14) * (0.6 + 0.5 * smoothstep(-0.65, 0.1, p.y)) * (0.9 + 0.15 * vnoise(p * 14.0));
    c3 = mix(c3, float3(0.4, 0.22, 0.1), 0.5 * smoothstep(0.55, 0.8, vnoise(p * 6.0 + 9.0)));       // rust
    c3 = mix(c3, float3(0.08), step(0.5, fract((p.x + p.y) * 9.0)) * step(abs(p.y - bc.y + 0.29), 0.035) * step(box, 0.0));   // hazard stripes
    if (min(skids, handle) < box) c3 = float3(0.25, 0.27, 0.3) * (0.6 + 0.6 * smoothstep(-0.7, 0.4, p.y));
    c3 *= lum;
    // the window and its bars
    float2 wq = p - bc - float2(0.0, 0.04);
    float win = sd_box(wq, float2(0.5, 0.17), 0.03);
    float3 level = v > 0.5 ? float3(0.3, 1.0, 0.5) : v > 0.2 ? float3(1.0, 0.75, 0.2) : float3(1.0, 0.25, 0.2);
    float blink = v > 0.2 ? 1.0 : 0.45 + 0.55 * step(0.0, sin(phase * 5.0));
    float lightSum = 0.0;
    if (win < 0.0) {
        c3 = float3(0.015, 0.025, 0.035);
        float bx = (wq.x + 0.46) / 0.92 * 5.0;
        float bi = floor(bx);
        float bar = step(0.12, fract(bx)) * step(fract(bx), 0.88) * step(abs(wq.y), 0.11) * step(0.0, bx) * step(bx, 5.0);
        float on = step(bi + 0.5, v * 5.0 + 0.49);
        if (busy) on = max(on, step(abs(fmod(phase * 3.0, 6.0) - bi - 0.5), 0.6) * 0.8);
        c3 += level * bar * (0.07 + 1.1 * on * blink);
        lightSum = bar * on * blink;
    }
    c3 = mix(c3, float3(0.5, 0.53, 0.56) * lum, (1.0 - smoothstep(0.0, 0.015, abs(win) - 0.012)) * step(box, 0.0));   // the frame
    c3 *= 0.6 + 0.4 * smoothstep(-0.74, -0.6, p.y);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    float edge = 1.0 - smoothstep(0.65, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(win, 0.0) * 7.0) * (0.12 + 0.3 * v) * blink * (1.0 - a) * edge * step(-0.7, p.y);
    return float4((c3 * a + level * halo) * col.a, (a + halo * 0.4) * col.a);
}

// The submarine, with what it needs down here: a headlamp cutting a cone into the dark, lit portholes, a turning
// propeller. p = c * (1.5, 0.9), facing +x.
float4 draw_trench_sub(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.9);
    p.y -= sin(phase * 0.9) * 0.02;
    float hull = sd_seg(p, float2(-0.78, 0.0), float2(0.42, 0.0)) - 0.32;
    float tower = sd_box(p - float2(-0.05, 0.4), float2(0.2, 0.14), 0.07);
    float scope = min(sd_seg(p, float2(0.0, 0.5), float2(0.0, 0.72)), sd_seg(p, float2(0.0, 0.72), float2(0.1, 0.72))) - 0.022;
    float finsT = min(sd_tri(p, float2(-0.95, 0.1), float2(-1.3, 0.34), float2(-1.2, 0.05)), sd_tri(p, float2(-0.95, -0.1), float2(-1.3, -0.34), float2(-1.2, -0.05)));
    float prop = (length((p - float2(-1.3, 0.0)) / float2(0.045, 0.06 + 0.2 * abs(sin(phase * 5.0)))) - 1.0) * 0.045;
    float skid = min(sd_box(p - float2(-0.15, -0.44), float2(0.5, 0.025), 0.02),
                     min(sd_seg(p, float2(-0.5, -0.3), float2(-0.5, -0.44)), sd_seg(p, float2(0.2, -0.3), float2(0.2, -0.44))) - 0.02);
    float2 lp = p - float2(0.62, -0.26);                                       // the lamp, under the nose
    float lamp = length(lp) - 0.075;
    float parts = min(min(tower, scope), min(min(finsT, prop), skid));
    float d = min(min(hull, parts), lamp);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 warm = float3(1.0, 0.93, 0.7);
    float3 c3 = float3(0.0);
    if (a > 0.001) {
        float2 nq = float2(0.0, p.y / 0.32);
        float lt = 0.35 + 0.75 * max(0.0, dot(normalize(float3(0.0, nq.y, sqrt(max(0.02, 1.0 - nq.y * nq.y)))), normalize(float3(-0.2, 0.8, 0.55))));
        c3 = col.rgb * lt * (0.92 + 0.1 * vnoise(p * 18.0));
        c3 *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.012, abs(abs(p.x + 0.15) - 0.4)));          // hull seams
        c3 = mix(c3, col.rgb * float3(0.6, 0.4, 0.3), 0.35 * smoothstep(0.55, 0.8, vnoise(p * 7.0)));
        if (parts < hull) c3 = col.rgb * (prop < min(tower, skid) ? 0.4 : 0.7) * (0.6 + 0.5 * smoothstep(-0.5, 0.7, p.y));
        for (int i = 0; i < 3; i++) {                                           // portholes: someone's home
            float pr = length(p - float2(-0.5 + float(i) * 0.36, 0.04));
            c3 = mix(c3, float3(0.25, 0.27, 0.3), 1.0 - smoothstep(0.1, 0.115, pr));
            c3 = mix(c3, warm * (0.75 + 0.25 * sin(phase * 0.7 + float(i))), 1.0 - smoothstep(0.07, 0.085, pr));
        }
        if (lamp < min(hull, parts)) c3 = warm * 1.3;
        c3 += warm * exp(-length(lp) * 5.0) * 0.4;
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.2;
        c3 += col.rgb * glow * 0.3;
    }
    // the beam: a cone ahead and a little down, thinning out
    float2 bq = float2(lp.x * 0.985 - lp.y * -0.17, lp.x * -0.17 + lp.y * 0.985);
    float along = max(bq.x, 0.0);
    float cone = (1.0 - smoothstep(0.12, 0.34, abs(bq.y) / (along + 0.08))) * step(0.0, bq.x);
    float edge = (1.0 - smoothstep(0.82, 1.0, abs(c.x))) * (1.0 - smoothstep(0.7, 1.0, abs(c.y)));
    float beam = cone * exp(-along * 1.3) * 0.42 * edge + exp(-dot(lp, lp) * 50.0) * 0.6;
    float halo = exp(-max(d, 0.0) * 20.0) * glow * 0.4 * edge;
    return float4((c3 * a + (warm * beam + col.rgb * halo) * (1.0 - a)) * col.a, (a + (beam * 0.5 + halo * 0.5) * (1.0 - a)) * col.a);
}

// A yeti crab in place of the crab (and walking the sand on its own): chalk-white, blind, its long arms out to
// both sides and thick with pale bristles where it farms the bacteria it eats; six legs stepping.
// p = c * (1.5, 0.9); the ground at y ≈ -0.81.
float4 draw_trench_yeti(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.5, 0.9);
    float gy = -0.81;
    float bob = sin(phase * 3.0) * 0.012;
    float2 q = float2(abs(p.x), p.y - bob);                                    // the same on both sides
    float sideK = p.x < 0.0 ? 1.7 : 0.0;
    float shell = (length((q - float2(0.0, -0.38)) / float2(0.4, 0.26)) - 1.0) * 0.26;
    // the arms: shoulder, elbow up and out, the claw reaching down; waving a little
    float wv = sin(phase * 1.4 + sideK) * 0.06;
    float2 sh = float2(0.3, -0.32), el = float2(0.78, -0.02 + wv), wr = float2(1.18, -0.3 + wv * 1.5);
    float arm = min(sd_seg(q, sh, el), sd_seg(q, el, wr)) - 0.065;
    float claw = min(sd_seg(q, wr, wr + float2(0.16, -0.12)), sd_seg(q, wr, wr + float2(0.05, -0.19))) - 0.035;
    float fuzz = vnoise(p * float2(46.0, 46.0)) * 0.07 * smoothstep(0.35, 0.6, q.x);
    float arms = min(arm, claw) - fuzz;
    // the legs: three each side, stepping in turn
    float legs = 1e3;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float st = sin(phase * 3.0 + fi * 2.1 + sideK) * 0.05;
        float lift = max(0.0, cos(phase * 3.0 + fi * 2.1 + sideK)) * 0.04;
        float2 hip = float2(0.25 + fi * 0.05, -0.48), knee = float2(0.5 + fi * 0.13, -0.36 - fi * 0.03), foot = float2(0.62 + fi * 0.17 + st, gy + lift);
        legs = min(legs, min(sd_seg(q, hip, knee), sd_seg(q, knee, foot)) - 0.03);
    }
    float d = min(min(shell, arms), legs);
    float aa = fwidth(shell) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    if (a <= 0.001 && glow < 0.01) return float4(0.0);
    float3 c3;
    if (shell <= min(arms, legs)) {
        float2 nq = (q - float2(0.0, -0.38)) / float2(0.4, 0.26);
        float3 n = normalize(float3(nq, sqrt(max(0.02, 1.0 - dot(nq, nq)))));
        c3 = col.rgb * (0.45 + 0.7 * max(0.0, dot(n, normalize(float3(-0.2, 0.8, 0.5)))));
        c3 *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.02, abs(q.x - 0.14 - 0.3 * (q.y + 0.38))));      // the shell's grooves
        c3 = mix(c3, col.rgb * 0.35, 1.0 - smoothstep(0.015, 0.028, length(q - float2(0.1, -0.2))));  // what's left of its eyes
    } else if (arms < legs) {
        // bristles: pale gold, streaked
        c3 = col.rgb * float3(1.0, 0.93, 0.7) * (0.6 + 0.5 * vnoise(p * float2(70.0, 22.0))) * (0.7 + 0.4 * smoothstep(-0.4, 0.1, q.y));
        if (claw < arm) c3 = col.rgb * float3(1.0, 0.85, 0.8) * 0.85;
    } else {
        c3 = col.rgb * 0.7 * (0.7 + 0.4 * smoothstep(gy, -0.4, q.y));
    }
    c3 *= 0.6 + 0.4 * smoothstep(gy, gy + 0.15, p.y);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.02, -d)) * 0.2;
    c3 += col.rgb * glow * 0.3;
    float edge = 1.0 - smoothstep(0.7, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 18.0) * glow * 0.45 * (1.0 - a) * edge * step(gy, p.y);
    return float4((c3 * a + col.rgb * halo) * col.a, (a + halo * 0.5) * col.a);
}

// Atolla, the alarm jellyfish, in place of the jellyfish: a deep red crowned bell, a skirt of lappets, a fringe of
// tentacles and one long one trailing. Its rim carries a ring of blue lights that turn like a pinwheel: lazily
// when all is well, fast and bright when something's wrong (extra.w: alert, error, waiting). p = c.
float4 draw_trench_atolla(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c;
    float alarm = (abs(extra.w - 4.0) < 0.5 || abs(extra.w - 5.0) < 0.5) ? 1.0 : abs(extra.w - 2.0) < 0.5 ? 0.6 : 0.0;
    float beat = sin(phase * 1.5);
    float2 bc = float2(0.0, 0.3);
    float rx = 0.52 * (1.0 - 0.06 * beat), ry = 0.34 * (1.0 + 0.08 * beat);
    float2 bq = p - bc;
    float bell = (length(bq / float2(rx, ry)) - 1.0) * ry;
    float hem = -0.06 - 0.05 * abs(sin(bq.x / rx * 9.0));                    // the lappets
    bell = max(bell, hem - bq.y);
    // the fringe of tentacles, and the long one
    float tent = 1e3;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float x0 = (fi - 4.0) / 4.0 * rx * 0.9;
        float len = (i == 4 ? 1.1 : 0.42 + 0.2 * hash21(float2(fi, 2.0)));
        float ty = clamp(p.y, bc.y - 0.06 - len, bc.y - 0.06);
        float k = (bc.y - 0.06 - ty) / len;
        float tx = x0 * (1.0 + 0.25 * k) + sin(ty * 9.0 + phase * 1.6 + fi * 1.3) * 0.045 * k;
        tent = min(tent, length(p - float2(tx, ty)) - mix(0.016, 0.005, k));
    }
    float d = min(bell, tent);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 red = mix(float3(0.85, 0.1, 0.16), col.rgb / max(0.05, max(col.r, max(col.g, col.b))), 0.3);
    float3 c3;
    float alpha = a;
    if (bell <= tent) {
        float dome = sqrt(max(0.0, 1.0 - dot(bq / float2(rx, ry), bq / float2(rx, ry))));
        c3 = red * (0.3 + 0.5 * dome + 0.35 * smoothstep(-0.05, 0.3, bq.y));
        c3 = mix(c3, red * 1.5 + 0.1, (1.0 - smoothstep(0.0, 0.03, abs(bq.y - 0.07 + 0.25 * (bq.x / rx) * (bq.x / rx)))) * 0.5);   // the crown's groove
        c3 *= 0.85 + 0.2 * abs(sin(bq.x / rx * 9.0)) * smoothstep(0.1, -0.1, bq.y);
        c3 += float3(1.0, 0.6, 0.6) * pow(dome, 8.0) * 0.12;
        alpha = a * 0.92;
    } else {
        c3 = red * 0.75;
        alpha = a * 0.75;
    }
    // the pinwheel: lights along the rim, the bright one running around
    float3 blue = float3(0.3, 0.7, 1.0);
    float speed = mix(1.2, 7.0, alarm);
    float ring = 0.0;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float2 lq = p - bc - float2((fi - 4.0) / 4.0 * rx * 0.92, -0.03 - 0.04 * (1.0 - abs(fi - 4.0) / 4.0));
        float run = pow(0.5 + 0.5 * sin(fi * 0.698 * 2.0 - phase * speed), mix(6.0, 2.0, alarm));
        ring += exp(-dot(lq, lq) * 700.0) * (0.25 + 0.2 * glow + (0.6 + 0.6 * alarm) * run);
    }
    ring = min(ring, 1.6);
    float edge = 1.0 - smoothstep(0.7, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(bell, 0.0) * 14.0) * (0.1 + 0.35 * alarm * (0.5 + 0.5 * sin(phase * speed)) + 0.3 * glow) * (1.0 - a) * edge;
    float3 rgb = c3 * alpha + blue * ring + mix(red, blue, alarm) * halo;
    return float4(rgb * col.a, min(1.0, max(alpha, ring * 0.7) + halo * 0.4) * col.a);
}
