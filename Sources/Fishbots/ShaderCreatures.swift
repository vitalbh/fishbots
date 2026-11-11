/// Drawings: the ray, the fish, the octopus and the jellyfish.
let shaderCreatures = #"""
float sd_tri(float2 p, float2 a, float2 b, float2 c) {
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float sg = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(q0, q0), sg * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(q1, q1), sg * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(q2, q2), sg * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float smin_k(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// stingray (Codex), seen from above and facing +x: a broad disc with pointed wing tips whose edges ripple in a wave
// running back along them, a raised middle, spots, eyes with spiracles, pelvic lobes and a long whip of a tail
float4 draw_ray(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(1.25, 0.8);
    float2 q = p - float2(0.12, 0.0);
    float th = atan2(q.y, q.x);
    float r = length(q);
    float side = abs(sin(th));
    float wave = sin(phase * 1.2 - q.x * 6.0);
    // a diamond: the front edges bulging forward, the back edges straight, the wing tips pointed (a superellipse,
    // its exponent changing from front to back); the wing edges ripple
    float by = 0.58 * (1.0 + 0.05 * wave * side);
    float2 qs = float2(q.x + 0.3 * pow(abs(q.y) / by, 1.6), q.y);                 // the wing tips swept back
    float front = qs.x > 0.0 ? 1.0 : 0.0;
    float ax = mix(0.36, 0.5, front);
    float n = mix(1.0, 1.7, front);
    float2 an = abs(qs) / float2(ax, by);
    float se = pow(pow(an.x, n) + pow(an.y, n), 1.0 / n);
    float disc = (se - 1.0) * 0.3;
    // pelvic lobes behind the disc, and the tail with a spine partway down
    float pelv = (length((float2(q.x + 0.38, abs(q.y) - 0.06)) / float2(0.09, 0.05)) - 1.0) * 0.05;
    float tw = sin(phase * 0.6 - p.x * 3.0) * 0.05;
    float2 t0 = float2(-0.3, 0.0), t1 = float2(-1.18, tw), pa = p - t0, ba = t1 - t0;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float tail = length(pa - ba * h) - mix(0.05, 0.008, h);
    float2 s0 = float2(-0.62, tw * 0.4), s1 = float2(-0.78, tw * 0.6 + 0.035), sa = p - s0, sb = s1 - s0;
    float spine = length(sa - sb * clamp(dot(sa, sb) / dot(sb, sb), 0.0, 1.0)) - 0.008;
    float d = min(min(disc, pelv), min(tail, spine));
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float rr = clamp(se, 0.0, 1.0);
    // the body is raised in the middle and thin at the wings: lit on the side toward the light, the wings' wave
    // showing as bands of light and shade
    float2 g = rr > 0.0 ? q / max(r, 1e-3) : float2(0.0);
    float lit = dot(g, normalize(float2(-0.3, 0.7))) * smoothstep(0.15, 0.9, rr);
    float3 c3 = base * (0.78 + 0.3 * lit) * (0.62 + 0.55 * (1.0 - rr * rr));
    c3 *= 1.0 + 0.28 * wave * smoothstep(0.3, 0.8, rr) * side;
    float ridge = (1.0 - smoothstep(0.0, 0.06, abs(q.y))) * smoothstep(0.35, -0.1, q.x) * step(disc, 0.0);
    c3 = mix(c3, c3 * 0.8, ridge * 0.5);                                            // the spine down its back
    // spots, larger in the middle, and a lighter rim on the wing edges
    float2 sg = q * 6.0;
    float2 sid = floor(sg);
    float2 so = float2(hash21(sid), hash21(sid + 3.7)) * 0.5 + 0.25;
    float spot = (1.0 - smoothstep(0.13, 0.2 + 0.08 * hash21(sid + 1.1), length(fract(sg) - so))) * step(0.4, hash21(sid + 8.0));
    c3 = mix(c3, mix(base * 1.5 + 0.15, float3(0.55, 0.8, 1.0), 0.35), spot * 0.75 * step(disc, 0.0) * (1.0 - smoothstep(0.75, 0.95, rr)));
    c3 = mix(c3, base * 1.2 + 0.1, smoothstep(0.86, 0.98, rr) * step(disc, 0.0) * 0.35);
    // the tail and the lobes: darker, the spine pale
    if (disc > 0.0) c3 = base * (pelv < 0.0 ? 0.75 : 0.6);
    if (spine < 0.0 && tail > 0.0) c3 = float3(0.85, 0.82, 0.72) * dot(base, float3(0.6));
    // eyes on top, each with a spiracle just behind it
    for (int k = -1; k <= 1; k += 2) {
        float2 e = float2(0.36, 0.1 * float(k));
        float re = length(p - e);
        c3 = mix(c3, c3 * 1.25 + 0.05, (1.0 - smoothstep(0.035, 0.05, re)) * 0.6);   // the bump
        c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.018, 0.026, re));
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.003, 0.008, length(p - e - float2(0.006, 0.008))));
        float sp = length((p - float2(0.28, 0.11 * float(k))) / float2(1.0, 0.6)) - 0.018;
        c3 = mix(c3, c3 * 0.35, 1.0 - smoothstep(0.0, 0.01, sp));
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.25;                          // a darker outline
    c3 += base * glow * 0.45;
    float a = inside * col.a;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    return float4(c3 * a + base * halo * 0.9, min(a + halo * 0.55, 1.0));
}


// Shape (extra.z): 0 oval, 1 elongated, 2 pufferfish, 3 angelfish, 6 lanternfish (the built-in fish kinds pass it).
// extra.y: pattern and cut.
float4 draw_fish(float2 c, float phase, float glow, float4 col, float4 extra, float4 aux) {
    float2 p = c * float2(1.25, 0.8);
    int sp = int(extra.z + 0.5);
    int pad = int(extra.y + 0.5) % 8;      // project pattern
    int cutKind = int(extra.y + 0.5) / 8;    // project cut
    bool slim = sp == 1 || sp == 6;
    // shape of each species: body center and radii, tail length and spread
    float cx = 0.1, rx = 0.62, ry = 0.36, L = 0.46, flare = 0.34;
    if (slim) { cx = 0.1; rx = 0.78; ry = 0.22; L = 0.36; flare = 0.28; }
    if (sp == 2) { cx = 0.14; rx = 0.5; ry = 0.44; L = 0.26; flare = 0.24; }
    if (sp == 3) { cx = 0.12; rx = 0.46; ry = 0.4; L = 0.32; flare = 0.3; }
    // extra.w: fatness (context used, 0…1) + 2 if sleeping
    bool asleep = extra.w > 1.5;
    float fatness = clamp(extra.w - (asleep ? 2.0 : 0.0), 0.0, 1.0);
    ry *= 1.0 + fatness * 0.65;
    rx *= 1.0 + fatness * 0.1;

    if (cutKind == 1) { L *= 1.7; flare *= 1.35; }   // veil tail
    // aging (aux.w = age 0…1 + 2 × veteran level): a long session grows a longer, fuller tail and more marked scales
    float vet = floor(aux.w / 2.0 + 0.001);
    float age = clamp(aux.w - vet * 2.0, 0.0, 1.0);
    L *= 1.0 + age * 0.4;
    flare *= 1.0 + age * 0.25;

    // the body undulates: a wave runs from head to tail, small at the head and wide at the tail
    p.y -= sin(phase - p.x * 2.5) * (0.014 + 0.07 * (1.0 - smoothstep(-0.9, 0.4, p.x)));

    // body: an egg, full behind the head and narrowing toward the tail, joined to the tail by a slim stalk
    float rear = smoothstep(cx + rx * 0.25, cx - rx, p.x);
    float taper = sp == 2 ? 0.12 : sp == 3 ? 0.25 : 0.42;
    float ryx = ry * (1.0 - taper * rear);
    float2 b = (p - float2(cx, 0.0)) / float2(rx, ryx);
    if (sp == 3) b.x *= 1.0 + 0.25 * abs(b.y);                // angelfish: diamond-shaped body
    float body = (length(b) - 1.0) * min(rx, ryx);
    float bx = cx - rx * 0.9;                                   // where the tail starts
    float2 sa = float2(cx - rx * 0.55, 0.0), sb = float2(bx, 0.0), spa = p - sa, sba = sb - sa;
    float stalk = length(spa - sba * clamp(dot(spa, sba) / dot(sba, sba), 0.0, 1.0)) - ry * (sp == 2 ? 0.3 : 0.24);
    body = smin_k(body, stalk, 0.06);

    // tail: a fan with a rounded or forked back edge
    float2 tb = float2(bx + 0.04, 0.0);
    float tail = sd_tri(p, tb, float2(bx - L, flare), float2(bx - L, -flare));
    tail = max(tail, length(p - tb) - length(float2(L, flare)) * 0.98);            // rounded back edge
    float fork = slim ? 0.45 : sp == 3 ? 0.0 : 0.22;                                // notch depth
    if (cutKind == 1) fork = 0.0;
    if (fork > 0.0) tail = max(tail, -sd_tri(p, float2(bx - L * (1.0 - fork), 0.0), float2(bx - L - 0.1, flare * 0.85), float2(bx - L - 0.1, -flare * 0.85)));
    tail -= 0.012;                                                                  // soft corners
    float2 rayRoot = tb + float2(0.05, 0.0);                                        // where the fin rays fan out from

    float fins;
    if (sp == 3) {
        // tall fins, up and down, swept back
        float up = sd_tri(p, float2(cx - 0.32, ry * 0.6), float2(cx + 0.12, ry * 0.75), float2(cx - 0.45, 0.78));
        float dn = sd_tri(p, float2(cx - 0.32, -ry * 0.6), float2(cx + 0.12, -ry * 0.75), float2(cx - 0.45, -0.78));
        fins = min(up, dn) - 0.01;
    } else {
        // dorsal: a swept-back sail on the back; ventral and anal: two small ones under the belly
        float fl = slim ? 0.5 : sp == 2 ? 0.2 : 0.36;               // base length
        float fh = slim ? 0.11 : sp == 2 ? 0.1 : 0.17;              // height
        float x0 = cx + rx * (slim ? 0.1 : 0.2);
        float dors = sd_tri(p, float2(x0, ry * 0.6), float2(x0 - fl, ry * (slim ? 0.35 : 0.45)), float2(x0 - fl * 0.85, ryx + fh)) - 0.02;
        float vx = cx - rx * 0.05;
        float vent = sd_tri(p, float2(vx, -ry * 0.6), float2(vx - 0.12, -ry * 0.55), float2(vx - 0.13, -ry - fh * 0.4)) - 0.012;
        float ax = cx - rx * 0.5;
        float anal = sd_tri(p, float2(ax, -ryx * 0.5), float2(ax - fl * 0.4, -ry * 0.3), float2(ax - fl * 0.42, -ry * 0.55 - fh * 0.2)) - 0.012;
        fins = min(dors, sp == 2 ? vent : min(vent, anal));
    }
    if (cutKind == 1) tail += sin(p.y * 14.0 + phase * 1.3) * 0.012;                                  // veil rippling
    if (cutKind == 2 && sp != 3) fins = min(fins, sd_tri(p, float2(cx - 0.38, ry * 0.7), float2(cx + 0.14, ry * 0.75),
                                                       float2(cx - 0.34, ry + 0.4)) - 0.01);           // tall dorsal
    if (cutKind == 3) {                                                                                  // long fins
        float2 a0 = float2(cx + 0.02, -ry * 0.25), a1 = float2(cx - 0.48, -ry - 0.26 + sin(phase * 0.8) * 0.05);
        float2 pa = p - a0, ba = a1 - a0;
        fins = min(fins, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.03);
    }
    // pectoral fin: a little paddle behind the gills that keeps fluttering (how a still fish keeps its balance)
    float pang = -0.45 + sin(phase * 1.9) * 0.42;
    float2 pq = p - float2(cx + rx * 0.3, -ry * 0.25);
    pq = float2(pq.x * cos(pang) - pq.y * sin(pang), pq.x * sin(pang) + pq.y * cos(pang));
    float pect = (length((pq - float2(-0.11, 0.0)) / float2(0.14, 0.05)) - 1.0) * 0.05;
    if (sp == 3) pect = 1e3;                                       // the angelfish has its tall fins instead

    float d = min(min(min(body, tail), fins), pect);
    float aa = fwidth(d) * (1.0 + aux.z * 3.5) + 1e-4;                // far away: softer edges (depth of field)
    float inside = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float yn = p.y / (ryx / 0.36);                                   // height on the flank, as on a 0.36-tall body
    float belly = 1.0 - smoothstep(-0.25, 0.1, yn);
    float3 c3 = mix(base, base * 0.5 + 0.5, belly * 0.55);
    c3 = mix(c3, base * 0.62, smoothstep(0.05, 0.32, yn) * 0.5);      // a darker back (countershading)
    if (body < 0.0) {
        if (sp == 2) {
            // pufferfish spots
            float2 g = p * 9.0;
            float spot = 1.0 - smoothstep(0.18, 0.28, length(fract(g) - 0.5));
            c3 = mix(c3, base * 0.45, spot * 0.6 * step(0.0, p.y + 0.05));
        } else {
            if (slim) c3 = mix(c3, float3(0.95, 0.98, 1.0), (1.0 - smoothstep(0.012, 0.032, abs(p.y - 0.01))) * 0.6 * step(p.x, cx + rx * 0.5)); // silver lateral stripe
            if (pad == 1) {                // stripes
                float st = smoothstep(0.42, 0.5, fract((p.x + 0.2) * 3.2)) * (1.0 - smoothstep(0.82, 0.9, fract((p.x + 0.2) * 3.2)));
                c3 = mix(c3, float3(1.0), st * 0.55);
            } else if (pad == 2) {         // spots
                float2 g = p * 8.0; g.y += floor(g.x) * 0.5;
                c3 = mix(c3, base * 0.45, (1.0 - smoothstep(0.12, 0.2, length(fract(g) - 0.5))) * 0.55);
            } else if (pad == 3) {         // gradient from head to tail
                c3 = mix(c3, c3.gbr * 0.85 + 0.1, 1.0 - smoothstep(-0.6, 0.5, p.x));
            } else if (pad == 4) {         // scales
                float2 q = p * float2(11.0, 13.0); q.x += fmod(floor(q.y), 2.0) * 0.5;
                float r = length(fract(q) - float2(0.5, 0.0));
                c3 = mix(c3, c3 * 0.62, smoothstep(0.4, 0.48, r) * (1.0 - smoothstep(0.5, 0.58, r)) * 0.7);
            } else if (pad == 5) {         // eye mask
                c3 = mix(c3, base * 0.22, (1.0 - smoothstep(0.06, 0.09, abs(p.x - (cx + rx * 0.6)))) * 0.85);
            }
        }
    } else {
        // fins: a thin membrane, lighter toward the edge, with rays fanning out from the root
        float2 rr = p - rayRoot;
        float ang = atan2(rr.y, -rr.x);
        if (tail >= 0.0) ang = atan2(rr.x - 0.3, rr.y < 0.0 ? -rr.y : rr.y) * 0.9 + rr.x * 3.0;   // other fins: rays sweep back
        float rays = 0.5 + 0.5 * cos(ang * 22.0);
        float edgeLit = 1.0 - smoothstep(0.0, 0.05, -d);
        c3 = mix(base * 0.7, base * 0.55 + 0.32, edgeLit * 0.6);
        c3 *= 0.86 + 0.18 * rays;
    }
    // eye
    float2 eyeP = float2(cx + rx * 0.6, ry * 0.18);
    float er = sp == 2 ? 0.07 : sp == 6 ? 0.075 : 0.058;
    if (asleep) {
        // sleeping: eye closed, a little curved line
        float2 q = p - eyeP;
        float arc = abs(q.y + q.x * q.x * 6.0) - 0.009;
        c3 = mix(c3, float3(0.05), (1.0 - smoothstep(0.0, 0.012, arc)) * step(abs(q.x), er));
    } else {
        // a light ring (an iris tinted by the body) around a dark pupil that looks where aux.xy points (the cursor,
        // food), a dark socket around it, and a catchlight
        float re = length(p - eyeP);
        c3 = mix(c3, c3 * 0.55, (1.0 - smoothstep(er * 1.05, er * 1.4, re)) * 0.6);
        c3 = mix(c3, mix(float3(0.94, 0.93, 0.86), base, 0.22), 1.0 - smoothstep(er * 0.88, er * 1.04, re));
        float2 look = clamp(aux.xy, float2(-1.0), float2(1.0)) * er * 0.35;
        c3 = mix(c3, float3(0.02), 1.0 - smoothstep(er * 0.56, er * 0.68, length(p - eyeP - look)));
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(er * 0.14, er * 0.3, length(p - eyeP - look - er * float2(0.22, 0.26))));
    }
    // mouth: a short dark line at the tip of the snout
    if (body < 0.0 && sp != 3) {
        float2 m = p - float2(cx + rx * 0.97, -ry * 0.12);
        float mouth = abs(m.y + m.x * 0.3) - 0.006;
        c3 = mix(c3, base * 0.3, (1.0 - smoothstep(0.0, 0.01, mouth)) * step(-0.07, m.x) * 0.8);
    }
    c3 *= 0.8 + 0.32 * (yn + 0.4);
    if (body < 0.0) {
        // the light from the surface on the upper flank, and a faint sheen of color that shifts as it swims
        float2 hs = (p - float2(cx + rx * 0.15, ry * 0.42)) / float2(rx * 0.7, ry * 0.3);
        c3 += float3(1.0) * pow(max(0.0, 1.0 - dot(hs, hs)), 2.0) * 0.18;
        float sheen = sin(p.x * 7.0 + phase * 0.15) * 0.5 + 0.5;
        float3 iri = 0.5 + 0.5 * cos(6.2831 * (sheen * 0.35 + float3(0.0, 0.33, 0.67)));
        c3 += (iri - 0.5) * (slim ? 0.12 : 0.06) * (1.0 - belly);
    }
    if (body < 0.0 && age > 0.05) {
        // the scales show more as the session goes on
        float2 sq = p * float2(11.0, 13.0); sq.x += fmod(floor(sq.y), 2.0) * 0.5;
        float sr = length(fract(sq) - float2(0.5, 0.0));
        c3 = mix(c3, c3 * 0.7, smoothstep(0.4, 0.48, sr) * (1.0 - smoothstep(0.5, 0.58, sr)) * age * 0.55);
    }
    if (vet >= 1.0 && body < 0.0) {
        // an old project's fish: a little pale scar across the flank
        float2 sa2 = float2(cx - rx * 0.12, ry * 0.32), sb2 = float2(cx - rx * 0.42, -ry * 0.05);
        float2 pa = p - sa2, ba = sb2 - sa2;
        float scar = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.007;
        c3 = mix(c3, base * 0.45 + 0.42, (1.0 - smoothstep(0.0, 0.006, scar)) * 0.75);
    }
    if (vet >= 2.0 && body >= 0.0) {
        // a very old one: gold along the edges of its fins and tail
        c3 = mix(c3, float3(1.0, 0.82, 0.38), smoothstep(-0.035, -0.008, d) * 0.7);
    }
    // gill cover: a curved edge behind the eye that lifts a little as it breathes
    if (body < 0.0 && sp != 2) {
        float breath = 0.5 + 0.5 * sin(phase * 0.45);
        float2 gc = float2(cx + rx * 0.62, -ry * 0.05);
        float gr = rx * 0.34 + breath * 0.008;
        float2 gq = p - gc;
        float arc = abs(length(gq * float2(1.0, 0.75)) - gr);
        float on = step(gq.x, 0.0) * (1.0 - smoothstep(ry * 0.55, ry * 0.75, abs(p.y + ry * 0.05)));
        c3 *= 1.0 - (1.0 - smoothstep(0.006, 0.02, arc)) * on * (0.2 + 0.1 * breath);
        c3 += base * 0.12 * (1.0 - smoothstep(0.0, 0.04, length(gq * float2(1.0, 0.75)) - gr)) * step(length(gq * float2(1.0, 0.75)), gr + 0.04) * step(gr, length(gq * float2(1.0, 0.75))) * on;
    }
    // rim light along the back, and a darker outline underneath, so the shape reads even when it's small or far
    if (body < 0.0) {
        float edge = 1.0 - smoothstep(0.0, 0.035, -body);
        c3 += float3(0.75, 0.9, 1.0) * edge * smoothstep(-0.1, 0.8, p.y / ry) * 0.32;
        c3 *= 1.0 - edge * smoothstep(0.1, -0.6, p.y / ry) * 0.35;
    }
    if (pect < 0.0 && body >= -0.01) c3 = base * 0.8 + 0.14;      // the fin outside the body
    else if (pect < 0.0) c3 = mix(c3, base * 0.8 + 0.2, 0.4);       // over the body: lighter, see-through
    c3 += base * glow * 0.45;

    // fins are a little see-through
    float finA = body < 0.0 || pect < 0.0 ? 1.0 : 0.82 + 0.18 * smoothstep(-0.06, -0.15, d);
    float a = inside * col.a * finA;
    if (sp == 6) {
        // lanternfish: a row of little lights along the belly, and a stalk with the light swinging in front of the head
        float lum = 0.0;
        for (int i = 0; i < 7; i++) {
            float t = float(i) / 6.0;
            float x = mix(cx + rx * 0.45, cx - rx * 0.8, t);
            float bxn = (x - cx) / rx;
            float y = -ry * (1.0 - taper * smoothstep(0.25, -1.0, bxn)) * sqrt(max(0.0, 1.0 - bxn * bxn)) * 0.62;
            float r = length(p - float2(x, y));
            lum += (exp(-r * r * 4000.0) + exp(-r * r * 600.0) * 0.18) * (0.65 + 0.35 * sin(phase * 0.9 + float(i) * 1.7));
        }
        lum *= col.a;
        // the stalk: a curve rising from the forehead and bending forward, the light hanging from its tip
        float sw = sin(phase * 0.4);
        float2 h0 = float2(cx + rx * 0.35, ry * 0.9), h1 = float2(cx + rx * 0.55 + sw * 0.02, ry + 0.34);
        float2 lz = float2(cx + rx + 0.12 + sw * 0.04, ry + 0.2 + cos(phase * 0.5) * 0.015);
        float stk = 1e3;
        float2 prev = h0;
        for (int i = 1; i <= 6; i++) {
            float t = float(i) / 6.0;
            float2 q = mix(mix(h0, h1, t), mix(h1, lz, t), t);
            float2 pa = p - prev, ba = q - prev;
            stk = min(stk, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - mix(0.009, 0.005, t));
            prev = q;
        }
        float hi = (1.0 - smoothstep(0.0, fwidth(stk) + 1e-4, stk)) * col.a;
        c3 = mix(c3, base, hi); a = max(a, hi);
        // the light: a small core inside a wide, soft glow that fades out before the edge of the quad, and lights the head
        float r = length(p - lz);
        float flick = 0.8 + 0.2 * sin(phase * 1.7) * sin(phase * 0.63 + 1.0);
        float room = 1.0 - smoothstep(0.55, 1.0, max(abs(c.x), abs(c.y)) / LANTERN_ROOM);
        float lamp = (exp(-r * r * 1600.0) * 0.85 + exp(-r * r * 140.0) * 0.35 + exp(-r * r * 16.0) * 0.26 + exp(-r * r * 3.5) * 0.13) * flick * col.a * room;
        c3 += float3(0.6, 1.0, 0.85) * exp(-r * r * 6.0) * 0.35 * flick;                     // the light falling on the head
        lum = lum * 0.9 + lamp;
        return float4(c3 * a * (1.0 - min(lum, 1.0)) + float3(0.6, 1.0, 0.85) * lum, min(1.0, a + lum * 0.8));
    }
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    float3 outc = c3 * a + base * halo * 0.9;
    return float4(outc, min(a + halo * 0.55, 1.0));
}

// little octopus (GitHub): a round mantle with a face, and six arms that curl at the tips, webbed at the base
// The leader of a school of sessions: a nautilus. Its striped shell, in the session's color, has a row of chambers
// along the back, one lit for each session of its school at work (lit: how many, 0…6).
float4 draw_nautilus(float2 c, float phase, float glow, float4 col, float lit) {
    float2 p = c * float2(1.25, 0.8);
    p.y -= 0.03 * sin(phase * 0.45);                                   // it bobs as it goes
    float2 sp = p - float2(-0.22, 0.1);
    float shell = length(sp) - 0.56;
    // the hood over the shell's opening, with the body under it
    float2 hp = p - float2(0.36, -0.06);
    float hood = (length(hp / float2(0.3, 0.24)) - 1.0) * 0.24;
    // the tentacles: a bunch of short ones reaching forward and down, waving
    float tent = 1e3, tentT = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float2 q = float2(0.5, -0.12 - 0.012 * fi);
        float a0 = mix(0.35, -1.25, fi / 7.0);
        for (int j = 0; j < 5; j++) {
            float t1 = float(j + 1) / 5.0;
            float a = a0 + sin(phase * 0.8 + fi * 1.1 - t1 * 3.0) * 0.35 * t1;
            float2 q1 = q + float2(cos(a), sin(a)) * (0.34 + 0.03 * sin(fi * 2.0)) / 5.0;
            float2 pa = p - q, ba = q1 - q;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float dd = length(pa - ba * h) - (0.04 * (1.0 - 0.75 * (float(j) + h) / 5.0) + 0.006);
            if (dd < tent) { tent = dd; tentT = (float(j) + h) / 5.0; }
            q = q1;
        }
    }
    float body = smin_k(hood, tent, 0.05);
    float d = min(shell, body);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    float onShell = 1.0 - smoothstep(-aa, aa, shell);

    // the body: the session's color, darker on the hood, with pale spots; the tentacles ringed
    float3 flesh = col.rgb * (0.55 + 0.4 * smoothstep(-0.5, 0.3, p.y));
    flesh = mix(flesh, col.rgb * 0.4 + 0.5, (1.0 - smoothstep(0.03, 0.05, length(fract(p * float2(9.0, 8.0)) - 0.5))) * 0.35 * step(hood, 0.0));
    if (tent < hood) flesh = mix(flesh, col.rgb * 0.5 + 0.42, step(0.5, fract(tentT * 6.0)) * 0.5);
    // the eye: a pale ring with a small dark pupil
    float re = length(p - float2(0.4, -0.1));
    flesh = mix(flesh, float3(0.95, 0.92, 0.85), 1.0 - smoothstep(0.065, 0.08, re));
    flesh = mix(flesh, float3(0.03), 1.0 - smoothstep(0.028, 0.04, re));

    // the shell: cream, round, with tiger stripes in the session's color fanning over the back from the whorl's center
    float3 cream = float3(0.96, 0.92, 0.84);
    float2 uc = sp - float2(0.1, -0.08);                                // the whorl's center, toward the opening
    float ur = length(uc), ua = atan2(uc.y, uc.x);
    float stripes = smoothstep(0.35, 0.6, sin(ua * 9.0 + ur * 7.0 + sin(ur * 20.0) * 0.4));
    float back = smoothstep(-0.9, 0.4, sin(ua - 2.2));                   // they fade toward the opening (in front, below)
    float3 sh = mix(cream, mix(col.rgb, float3(0.55, 0.22, 0.1), 0.35), stripes * back * smoothstep(0.1, 0.25, ur));
    float whorl = 0.07 * exp(0.22 * (ua + 3.1416));                      // the inner turn of the spiral
    sh *= 1.0 - 0.35 * (1.0 - smoothstep(0.008, 0.02, abs(ur - whorl))) * step(ur, 0.3);
    float3 nrm = normalize(float3(sp / 0.56, sqrt(max(0.0, 1.0 - dot(sp, sp) / 0.3136))));
    float lam = clamp(dot(nrm, normalize(float3(-0.3, 0.7, 0.6))), 0.0, 1.0);
    sh *= 0.5 + 0.62 * lam;
    sh += pow(lam, 14.0) * 0.3;
    // the chambers along the back: one lit for each session at work
    for (int i = 0; i < 6; i++) {
        float ca = 0.55 + float(i) * 0.5;                                // from the top in front, around the back
        float dotd = length(sp - float2(cos(ca), sin(ca)) * 0.43);
        float on = step(float(i) + 0.5, lit);
        float lamp = 1.0 - smoothstep(0.035, 0.06, dotd);
        // unlit: a small dark dimple; lit: a golden lamp with a pale heart and a warm halo on the shell around it
        float3 gold = mix(float3(1.0, 0.62, 0.12), float3(1.0, 0.95, 0.75), 1.0 - smoothstep(0.0, 0.014, dotd));
        sh = mix(sh, mix(sh * 0.6, gold, on), lamp);
        float halo = on * exp(-dotd * dotd / 0.016) * (0.45 + 0.15 * sin(phase * 1.5 + float(i)));
        sh = mix(sh, float3(1.0, 0.66, 0.2), halo * (1.0 - lamp) * 0.7);
    }
    float3 c3 = mix(flesh, sh, onShell);
    c3 += col.rgb * glow * 0.35;
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.25;                // a darker rim
    return float4(c3 * inside, inside);
}

float4 draw_octo(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(1.25, 0.8);
    float pulse = 1.0 + 0.05 * sin(phase * 0.8);
    // mantle: a soft egg leaning back a little, with the face below it
    float2 mp = p - float2(-0.03 * (p.y - 0.1), 0.3);
    float2 mq = mp / (float2(0.33, 0.33) * float2(pulse, 2.0 - pulse));
    mq.x *= 1.0 + 0.18 * smoothstep(0.0, -0.8, mq.y);                  // narrower toward the face
    float mantle = (length(mq) - 1.0) * 0.3;
    float face = (length((p - float2(0.0, 0.03)) / float2(0.3, 0.17)) - 1.0) * 0.15;
    float head = smin_k(mantle, face, 0.1);

    // the arms: each one a chain of segments, thick at the base and thin at the tip, curling outward
    float arm = 1e3, armT = 0.0, side = 0.0;
    for (int i = 0; i < 6; i++) {
        float s = (float(i) - 2.5) / 2.5;                                  // -1…1, from the left arm to the right one
        float2 q = float2(s * 0.19, 0.0);
        float len = 0.62 - 0.08 * (1.0 - abs(s));
        for (int j = 0; j < 8; j++) {
            float t0 = float(j) / 8.0, t1 = float(j + 1) / 8.0;
            float ang = -1.5708 + s * (0.45 + 1.5 * t1 * t1)
                      + sin(phase * 0.9 + float(i) * 1.3 - t1 * 4.0) * 0.55 * t1;
            float2 q1 = q + float2(cos(ang), sin(ang)) * len / 8.0;
            float2 pa = p - q, ba = q1 - q;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float t = mix(t0, t1, h);
            float2 off = pa - ba * h;
            float dd = length(off) - (0.085 * (1.0 - 0.82 * t) + 0.008);
            if (dd < arm) {
                arm = dd; armT = t;
                // which side of the arm (the suckers are on the inside of the curl)
                side = (ba.x * off.y - ba.y * off.x) / max(length(ba), 1e-4) * (s < 0.0 ? 1.0 : -1.0);
            }
            q = q1;
        }
    }
    float d = smin_k(head, arm, 0.07);                                   // the web between the arms
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    // round shading: lit from the surface, darker toward the arms and the edges
    float3 c3 = base * (0.62 + 0.45 * smoothstep(-0.6, 0.6, p.y));
    float onHead = 1.0 - smoothstep(-0.01, 0.03, head);
    float3 nrm = float3(mq.x * 0.9, mq.y, sqrt(max(0.0, 1.0 - dot(mq, mq))));
    float lit = clamp(dot(normalize(nrm), normalize(float3(-0.35, 0.7, 0.6))), 0.0, 1.0);
    c3 = mix(c3, base * (0.55 + 0.6 * lit), onHead * (1.0 - smoothstep(-0.3, 0.1, -mantle * 3.0 + 0.0) * 0.0));
    c3 += float3(1.0) * pow(lit, 12.0) * 0.35 * onHead * step(mantle, 0.0);       // a glossy highlight on the mantle
    // mottled skin: darker patches and little light freckles
    float n = vnoise(p * 9.0) * 0.6 + vnoise(p * 19.0) * 0.4;
    c3 *= 0.85 + 0.25 * smoothstep(0.35, 0.75, n);
    c3 = mix(c3, base * 0.5 + 0.45, (1.0 - smoothstep(0.035, 0.05, length(fract(p * float2(8.0, 7.0) + 0.3) - 0.5))) * 0.3 * onHead * step(0.12, p.y));
    // the arms: lighter underneath, with rows of suckers on the inside of the curl
    float onArm = 1.0 - onHead;
    if (arm < 0.0 && armT > 0.12) {
        float r = 0.085 * (1.0 - 0.82 * armT) + 0.008;
        c3 = mix(c3, base * 0.65 + 0.3, smoothstep(-0.2, 0.6, side / r) * 0.45 * onArm);
        float row = abs(fract(armT * 11.0) - 0.5) * (0.62 / 11.0) * 2.0;
        float dot2 = length(float2(row, side - r * 0.35));
        c3 = mix(c3, float3(0.98, 0.9, 0.88) * (base * 0.3 + 0.7), (1.0 - smoothstep(r * 0.3, r * 0.48, dot2)) * 0.8 * onArm);
    }
    // eyes: raised bumps on top of the face, golden, with the octopus's wide horizontal pupil and a heavy lid
    for (int k = -1; k <= 1; k += 2) {
        float2 e = float2(0.13 * float(k), 0.12);
        float re = length((p - e) / float2(1.0, 0.95));
        c3 = mix(c3, c3 * 1.15 + 0.05, (1.0 - smoothstep(0.085, 0.11, re)) * 0.6);         // the bump
        c3 = mix(c3, c3 * 0.45, (1.0 - smoothstep(0.07, 0.085, re)) * 0.7);              // a dark ring around the eye
        c3 = mix(c3, float3(0.98, 0.93, 0.74), 1.0 - smoothstep(0.06, 0.07, re));        // iris
        float2 pp = (p - e - float2(0.0, -0.004)) / float2(0.046, 0.026);
        c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.85, 1.12, length(pp)));            // the wide horizontal pupil
        c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.009, 0.017, length(p - e - float2(-0.02, 0.028))));
        float lid = (p.y - e.y) - 0.05 + 0.012 * sin(phase * 0.3);                        // a lid over the top of the eye
        c3 = mix(c3, base * 0.8, step(0.0, lid) * (1.0 - smoothstep(0.07, 0.08, re)));
    }
    // rim light along the top of the mantle
    float edge = 1.0 - smoothstep(0.0, 0.03, -d);
    c3 += float3(0.75, 0.9, 1.0) * edge * smoothstep(0.1, 0.6, p.y) * 0.3;
    c3 *= 1.0 - edge * smoothstep(0.1, -0.5, p.y) * 0.3;
    c3 += base * glow * 0.45;
    float a = inside * col.a;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    return float4(c3 * a + base * halo * 0.9, min(a + halo * 0.55, 1.0));
}

float4 draw_jelly(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(1.2, 1.8);
    float pulse = 1.0 + 0.08 * sin(phase * 1.6);
    float2 b = (p - float2(0.0, 0.55)) / (float2(0.75, 0.6) * float2(pulse, 2.0 - pulse));
    float bell = length(b) - 1.0;
    float cut = 0.55 - 0.05 * sin(p.x * 14.0 + phase * 3.0) - p.y;
    float dome = max(bell * 0.6, cut);
    float aa = fwidth(dome) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, dome);
    float a = inside * (0.35 + 0.35 * (1.0 - length(b)));

    float tentD = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float x = -0.5 + fi * 0.25 + sin(phase * 1.2 + p.y * 5.0 + fi) * 0.07 * (0.55 - p.y);
        float w = 0.025;
        float line = 1.0 - smoothstep(w * 0.3, w, abs(p.x - x));
        line *= step(p.y, 0.55);
        line *= smoothstep(-1.65, -0.4, p.y);
        tentD = max(tentD, line);
    }
    a = max(a, tentD * 0.45);
    float fade = 1.0 - smoothstep(0.5, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(dome, 0.0) * 6.0) * glow * 0.5 * (1.0 - inside) * fade;
    float3 c3 = col.rgb * (0.7 + glow * 0.8);
    return float4(c3 * a * col.a + col.rgb * halo, min(1.0, a * col.a + halo * 0.5));
}

float sd_seg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float sd_box(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

"""#
