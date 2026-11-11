/// The sprite pass, first half: each sprite's quad.
let shaderSpriteVertex = #"""
struct SpOut {
    float4 position [[position]];
    float2 local;
    float2 world;
    float kind;
    float glow;
    float phase;
    float4 color;
    float4 extra;
    float4 aux;
};

// the presences' quads (Scene.swift), relative to their size
float2 presence_extent(int kind) {
    switch (kind) {
        case 25: return float2(1.6, 0.7);      // shark
        case 26: return float2(1.5, 0.75);     // submarine
        case 27: return float2(0.9, 0.5);      // bottle
        case 28: return float2(0.55, 0.9);     // hourglass
        case 29: return float2(0.8, 0.95);     // anchor
        case 31: return float2(1.05, 1.05);    // helm
        default: return float2(0.8, 1.1);      // flag
    }
}

float2 fish_extent(int k);           // each kind of fish's quad (generated with the kinds)

vertex SpOut sprite_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device Sprite* sp [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
    float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
    Sprite s = sp[iid];
    float2 c = corners[vid];
    float2 ext;
    if (s.kind < 0.5) ext = fish_extent(int(s.extra.z + 0.5)) * s.size * (int(s.extra.z + 0.5) == LANTERN_KIND ? LANTERN_ROOM : 1.0); // the lanternfish: room for its light
    else if (s.kind > 34.5) ext = s.aux.xy * s.size;                  // a pack's scenery or creature: its own extent
    else if (s.kind > 33.5) ext = float2(s.size);                     // coral
    else if (s.kind > 32.5) ext = float2(s.size);                     // mote (marine snow)
    else if (s.kind > 31.5) ext = float2(1.0, 0.28) * s.size;         // shadow on the sand
    else if (s.kind > 24.5) ext = presence_extent(int(s.kind + 0.5)) * s.size;   // presences (Scene.swift)
    else if (s.kind > 22.5) ext = float2(1.15, 1.0) * s.size;         // chest (room for the glow above)
    else if (s.kind > 21.5) ext = float2(1.1, 0.95) * s.size;         // shell
    else if (s.kind > 20.5) ext = float2(1.3, 0.85) * s.size;         // rock
    else if (s.kind > 19.5) ext = float2(0.8, 1.0) * s.size;          // foreground (blurred seaweed)
    else if (s.kind > 18.5) ext = float2(2.2, 0.7) * s.size;          // whale
    else if (s.kind > 16.5) ext = float2(s.size);                     // starfish
    else if (s.kind > 15.5) ext = float2(1.0, 0.7) * s.size;          // snail
    else if (s.kind > 14.5) ext = float2(1.3, 0.9) * s.size;          // turtle
    else if (s.kind > 13.5) ext = float2(1.2, 0.8) * s.size;          // crab
    else if (s.kind > 12.5) ext = float2(0.75, 1.2) * s.size;         // seahorse
    else if (s.kind > 9.5) ext = float2(s.size);                      // ink, fogged glass, pearl
    else if (s.kind > 3.5 && s.kind < 4.5) ext = float2(s.size * 2.2); // sparkle: room for the halo
    else if (s.kind > 8.5) ext = (s.extra.y > 0.5 && s.extra.y < 1.5 ? float2(1.0, 0.32)      // aurora: band
                                  : s.extra.y > 1.5 ? float2(0.3, 1.0) : float2(0.45, 1.0)) * s.size; // sunbeam / curtain
    else if (s.kind > 7.5) ext = float2(1.0, 0.22) * s.size;          // ripple on the surface
    else if (s.kind > 6.5) ext = float2(s.size, max(1.0, s.extra.w) * 2.0); // line
    else if (s.kind > 5.5) ext = float2(1.2, 0.6) * s.size;           // battery
    else if (s.kind > 4.5) ext = float2(1.2, 1.8) * s.size;           // jellyfish
    else ext = float2(s.size);
    float2 lp = c * ext;
    // extra.x: the sign mirrors vertically (a fish facing left); the size squeezes it sideways (a fish mid-turn)
    lp.y *= s.extra.x < 0.0 ? -1.0 : 1.0;
    lp.x *= max(abs(s.extra.x), 0.05);
    float2 w = float2(lp.x * s.dir.x - lp.y * s.dir.y, lp.x * s.dir.y + lp.y * s.dir.x);
    float2 world = s.pos + w;
    SpOut o;
    o.position = float4(world / u.res * 2.0 - 1.0, 0, 1);
    o.local = c;
    o.world = world;
    o.kind = s.kind;
    o.glow = s.glow;
    o.phase = s.phase;
    o.color = s.color;
    o.extra = s.extra;
    o.aux = s.aux;
    return o;
}

"""#

/// The sprite pass, second half: the kinds from FishKinds and the packs go in at the marker, then every sprite kind is drawn.
let shaderSpriteFragment = #"""
// @fish-kinds

// How much of each sprite kind glows (goes to the bloom). The rest only hides the glow behind it.
float emissive(float k, float glow) {
    if (k < 0.5) return clamp(glow, 0.0, 1.0) * 0.3;             // fish: when they light up (notes, waiting, a click)
    if (k < 1.5) return 0.12;                                      // bubble
    if (k < 2.5) return 0.5;                                       // ring
    if (k < 3.5) return 0.2;                                       // food
    if (k < 4.5) return 1.0;                                       // sparkle, fireworks
    if (k < 5.5) return 0.45;                                      // jellyfish
    if (k < 6.5) return 0.35;                                      // battery window
    if (k < 7.5) return 0.6;                                       // lines (constellation, shooting star)
    if (k < 8.5) return 0.3;                                       // ripple on the surface
    if (k < 9.5) return 0.35;                                      // aurora
    if (k < 11.5) return 0.0;                                      // ink, fogged glass
    if (k < 12.5) return clamp(glow, 0.0, 1.0) * 0.7;              // pearl: when it's new
    if (k < 22.5) return 0.0;                                      // creatures, whale, seaweed, rocks, shell
    if (k < 23.5) return 0.45;                                     // chest: the gold in the gap
    if (k < 24.5) return 0.7;                                      // music note
    if (k < 31.5) return 0.12 + clamp(glow, 0.0, 1.0) * 0.6;       // presences: their state's halo
    if (k < 32.5) return 0.0;                                      // shadow
    if (k < 33.5) return 0.25;                                     // marine snow
    if (k > 45.5) return 0.1 + clamp(glow, 0.0, 1.0) * 0.5;        // the clutch of eggs: when it stirs
    if (k > 44.5) return 0.15 + clamp(glow, 0.0, 1.0) * 0.5;       // pilot light
    return 0.0;                                                    // coral
}

fragment Frag2 sprite_fragment(SpOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 c = in.local;
    float r = length(c);
    float k = in.kind;
    float4 outc;
    if (k < 0.5) {
        if (int(in.extra.z + 0.5) == LANTERN_KIND) c *= LANTERN_ROOM;                               // its quad is bigger
        outc = draw_kind(int(in.extra.z + 0.5), c, in.phase, in.glow, in.color, in.extra, in.aux);   // extra.z: the fish kind
        if (outc.a > 0.01) {
            // the same background light passes over the fish
            float2 uw = in.world / u.res;
            float2 q = float2(uw.x * (u.res.x / u.res.y), uw.y);
            float caust = clamp(caustic(float2(q.x, q.y * 1.5) * 5.0 - 250.0, u.time * 0.35), 0.0, 1.0);
            float r1 = sin((q.x + q.y * 0.35) * 9.0 + u.time * 0.25) * 0.5 + 0.5;
            float r2 = sin((q.x - q.y * 0.20) * 15.0 - u.time * 0.17) * 0.5 + 0.5;
            float sunRay = pow(r1 * r2, 3.0) * smoothstep(0.1, 1.0, uw.y);
            float lum = (caust * 0.32 + sunRay * 0.22) * u.light * (0.35 + uw.y);
            // scales glittering near the surface
            float twinkle = pow(max(0.0, sin(in.world.x * 0.9 + u.time * 3.1) * sin(in.world.y * 1.3 - u.time * 2.3)), 14.0)
                       * smoothstep(0.62, 0.92, uw.y) * u.light;
            outc.rgb += outc.a * (float3(0.65, 0.9, 0.9) * lum + float3(1.0) * twinkle * 0.7);
        }
    } else if (k < 1.5) {          // bubble
        float edge = 1.0 - smoothstep(0.82, 1.0, r);
        float rim = smoothstep(0.55, 0.92, r);
        float hl = 1.0 - smoothstep(0.0, 0.28, length(c - float2(-0.35, 0.35)));
        float a = edge * (0.12 + 0.5 * rim + 0.6 * hl) * 0.8 * clamp(in.glow, 0.0, 1.0);
        outc = float4(in.color.rgb * a, a);
    } else if (k < 2.5) {          // note ring
        float band = exp(-pow((r - 0.8) / 0.08, 2.0)) * in.glow;
        outc = float4(in.color.rgb * band, band) * 0.8;
    } else if (k < 3.5) {          // food
        float a = (1.0 - smoothstep(0.6, 1.0, r)) * in.glow;
        outc = float4(in.color.rgb * a, a);
    } else if (k < 4.5) {          // sparkle: bright core, halo and a wide soft glow around it
        float rr = r * 2.2;
        float core = exp(-rr * rr * 40.0), halo = exp(-rr * rr * 4.0), broad = exp(-r * r * 3.5);
        float a = (halo * 0.8 + core * 0.7 + broad * 0.3) * in.glow;
        outc = float4(mix(in.color.rgb, float3(1.0), core * 0.5) * a, (halo * 0.8 + core * 0.7) * in.glow * 0.75 + broad * 0.08 * in.glow);
    } else if (k < 5.5) {
        outc = draw_jelly(c, in.phase, in.glow, in.color);
    } else if (k < 6.5) {
        outc = draw_battery(c, in.glow, in.phase, in.extra, in.world, u.res);
    } else if (k < 7.5) {          // thin line (constellation, sheet music)
        float a = (1.0 - smoothstep(0.15, 1.0, abs(c.y))) * (1.0 - smoothstep(0.92, 1.0, abs(c.x))) * in.glow;
        outc = float4(in.color.rgb * a, a) * 0.7;
    } else if (k < 8.5) {          // flattened ripple on the surface
        float band = (exp(-pow((r - 0.8) / 0.07, 2.0)) + exp(-pow((r - 0.55) / 0.05, 2.0)) * 0.4) * in.glow;
        outc = float4(in.color.rgb * band, band) * 0.95;
    } else if (k > 9.5 && k < 10.5) {   // ink / murky water: dark soft cloud
        float n = vnoise(c * 3.0 + in.position.xy * 0.004);
        float border = 1.0 - smoothstep(0.55, 1.0, max(abs(c.x), abs(c.y)));
        float a = exp(-r * r * 3.0) * (0.6 + 0.4 * n) * in.glow * 0.55 * border;
        outc = float4(in.color.rgb * a, a);
    } else if (k > 10.5 && k < 11.5) {  // fogged glass: light textured mist
        float n = vnoise(c * 5.0 + float2(in.phase, 0.0)) * 0.6 + vnoise(c * 13.0) * 0.4;
        float border = 1.0 - smoothstep(0.5, 1.0, max(abs(c.x), abs(c.y)));
        float a = exp(-r * r * 3.2) * (0.55 + 0.45 * n) * in.glow * 0.3 * border;
        outc = float4(in.color.rgb * a, a);
    } else if (k > 45.5) {             // scenery: the clutch of eggs (glow: how stirred)
        outc = draw_eggs(c, in.phase, in.glow, in.color);
    } else if (k > 44.5) {             // a pilot light on the side glass (glow: how bright; extra.yzw: the lamp's color)
        outc = draw_pilot(c, in.glow, in.color, in.extra.yzw);
    } else if (k > 43.5) {             // a manatee (the lagoon's)
        outc = draw_manatee(c, in.phase, in.color);
    } else if (k > 42.5) {             // mangrove roots (the lagoon's)
        outc = draw_mangrove(c, in.phase, in.color);
    } else if (k > 41.5) {             // a sunken ship far away (the deep sea's)
        outc = draw_wreck(c, in.phase, in.color);
    } else if (k > 40.5) {             // scenery: an old diving helmet (the deep sea's)
        outc = draw_diving_helmet(c, in.phase, in.color);
    } else if (k > 39.5) {             // sunfish passing (built-in creature)
        outc = draw_sunfish(c, in.phase, in.color);
    } else if (k > 38.5) {             // anglerfish (built-in creature; extra.y: how open its mouth is)
        outc = draw_anglerfish(c, in.phase, in.extra.y, in.color);
    } else if (k > 37.5) {             // frost on the glass (glow: how much; extra.y: the window's aspect)
        outc = draw_frost(c, u.time, in.glow, in.extra.y);
    } else if (k > 36.5) {             // a pack's presence (extra.z: its index, extra.w: its state)
        outc = draw_presence_pack(int(in.extra.z + 0.5), c, in.phase, in.glow, in.color, in.extra);
    } else if (k > 35.5) {             // a pack's creature (extra.z: its index)
        outc = draw_fauna_pack(int(in.extra.z + 0.5), c, in.phase, in.glow, in.color, in.extra);
    } else if (k > 34.5) {             // a pack's scenery (extra.z: its index)
        outc = draw_scenery_pack(int(in.extra.z + 0.5), c, in.phase, in.glow, in.color, in.extra);
    } else if (k > 33.5) {             // scenery: coral (phase: 0 branching, 1 sea fan, 2 brain)
        outc = draw_coral(c, in.phase, u.time, in.color);
    } else if (k > 32.5) {             // mote of marine snow: a tiny soft speck
        float a = exp(-r * r * 4.5) * in.glow;
        outc = float4(in.color.rgb * a, a);
    } else if (k > 31.5) {             // soft shadow on the sand (glow: how dark)
        float a = (1.0 - smoothstep(0.15, 1.0, r)) * in.glow;
        outc = float4(0.0, 0.0, 0.0, a);
    } else if (k > 24.5) {             // presences (Scene.swift)
        outc = draw_presence(int(k + 0.5), c, in.phase, in.glow, in.color, in.extra);
    } else if (k > 23.5) {             // a music note rising from the music fish
        outc = draw_note(c, in.glow, in.color);
    } else if (k > 22.5) {             // scenery: chest
        // extra.z: the theme's chest (1 the deep sea's safe, 2 the lagoon's fish trap)
        outc = in.extra.z > 1.5 ? draw_fish_trap(c, in.phase, in.glow, in.color, in.extra.y)
             : in.extra.z > 0.5 ? draw_safe(c, in.phase, in.glow, in.color, in.extra.y)
                                : draw_chest(c, in.phase, in.glow, in.color, in.extra.y);
    } else if (k > 21.5) {             // scenery: big shell
        outc = in.extra.y > 0.5 ? draw_oyster(c, in.phase, in.color) : draw_shell(c, in.phase, in.color);   // extra.y: the oyster
    } else if (k > 20.5) {             // scenery: rock
        outc = draw_rock(c, in.phase, in.color);
    } else if (k > 19.5) {             // foreground: tuft of dark blurred seaweed, in front of everything
        float2 p = c;
        float a = 0.0;
        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            float x0 = -0.6 + fi * 0.24 + sin(fi * 3.7) * 0.08;
            float tallness = 0.55 + fract(sin(fi * 11.3) * 47.0) * 0.45;
            float k01 = clamp((p.y + 1.0) / (2.0 * tallness), 0.0, 1.0);
            float x = x0 + sin(in.phase * 0.5 + fi * 1.3 + p.y * 2.0) * 0.06 * k01 + k01 * k01 * 0.15 * sin(fi);
            float w = 0.12 * (1.0 - 0.7 * k01);
            float leaf = (1.0 - smoothstep(w * 0.2, w * 1.6, abs(p.x - x))) * (1.0 - smoothstep(tallness * 2.0 - 1.15, tallness * 2.0 - 0.95, p.y));
            a = max(a, leaf);
        }
        a *= 1.0 - smoothstep(0.75, 1.0, abs(p.x));
        float3 tint = in.color.rgb * (0.6 + 0.4 * (p.y + 1.0) * 0.5);
        outc = float4(tint * a, a) * in.glow;
    } else if (k > 18.5) {             // whale in the distance
        outc = draw_whale(c, in.phase, in.color);
    } else if (k > 16.5) {             // starfish: five arms, one moving
        float ang = atan2(c.y, c.x);
        float arm = pow(0.5 + 0.5 * cos(5.0 * ang + 0.3 + sin(in.phase * 0.7) * 0.15 * step(0.0, sin(ang * 2.5))), 2.0);
        float radius = 0.32 + 0.55 * arm;
        float d = length(c) - radius;
        float inside = 1.0 - smoothstep(-0.03, 0.03, d);
        float3 col = in.color.rgb * (0.75 + 0.35 * (1.0 - length(c)));
        col = mix(col, in.color.rgb * 1.3 + 0.1, (1.0 - smoothstep(0.05, 0.09, length(fract(c * 5.0) - 0.5))) * 0.5);
        outc = float4(col * inside, inside);
    } else if (k > 15.5) {             // snail: spiral shell and body with little antennae
        float2 p = c * float2(1.0, 0.7);
        float2 q = p - float2(-0.05, 0.12);
        float shell = length(q) - 0.42;
        float spiral = sin(atan2(q.y, q.x) + length(q) * 22.0) * 0.5 + 0.5;
        float2 b0 = float2(-0.55, -0.32), b1 = float2(0.6, -0.32), pa = p - b0, ba = b1 - b0;
        float bodyD = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.1;
        float antenna = 1e3;
        for (int i = 0; i < 2; i++) {
            float2 t0 = float2(0.55, -0.25), t1 = float2(0.72 + float(i) * 0.1, 0.05 + sin(in.phase * 2.0 + float(i)) * 0.03);
            float2 qa = p - t0, ta = t1 - t0;
            antenna = min(antenna, length(qa - ta * clamp(dot(qa, ta) / dot(ta, ta), 0.0, 1.0)) - 0.02);
        }
        float dc = min(bodyD, antenna);
        float ic = 1.0 - smoothstep(-0.02, 0.02, shell), ib = 1.0 - smoothstep(-0.02, 0.02, dc);
        float3 col = mix(float3(0.55, 0.55, 0.5), in.color.rgb * (0.6 + 0.5 * spiral), ic);
        outc = float4(col * max(ic, ib), max(ic, ib));
    } else if (k > 14.5) {             // turtle in profile
        outc = draw_turtle(c, in.phase, in.color);
    } else if (k > 13.5) {             // crab: body, claws, walking legs and stalked eyes
        float2 p = c * float2(1.2, 0.8);
        float d = length(p / float2(0.45, 0.27)) - 1.0;
        d *= 0.27;
        for (int s = -1; s <= 1; s += 2) {
            float sx = float(s);
            float claw = length(p - float2(sx * 0.66, 0.24)) - 0.14;
            claw = max(claw, -(length(p - float2(sx * 0.76, 0.33)) - 0.06));
            float2 a0 = float2(sx * 0.35, 0.08), a1 = float2(sx * 0.6, 0.2), pa = p - a0, ba = a1 - a0;
            float arm = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.04;
            float eye = length(p - float2(sx * 0.13, 0.43)) - 0.05;
            float2 h0 = float2(sx * 0.11, 0.2), h1 = float2(sx * 0.13, 0.42), qa = p - h0, qb = h1 - h0;
            float stalk = length(qa - qb * clamp(dot(qa, qb) / dot(qb, qb), 0.0, 1.0)) - 0.02;
            d = min(d, min(min(claw, arm), min(eye, stalk)));
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                float stride = sin(in.phase * 9.0 + fi * 2.1 + sx) * 0.05 * in.glow;
                float2 l0 = float2(sx * (0.28 - fi * 0.06), -0.06 - fi * 0.06), l1 = float2(sx * (0.62 - fi * 0.05), -0.36 - fi * 0.04 + stride);
                float2 la = p - l0, lb = l1 - l0;
                d = min(d, length(la - lb * clamp(dot(la, lb) / dot(lb, lb), 0.0, 1.0)) - 0.025);
            }
        }
        float inside = 1.0 - smoothstep(-0.012, 0.012, d);
        float3 col = in.color.rgb * (0.75 + 0.4 * (p.y + 0.3));
        for (int s = -1; s <= 1; s += 2) col = mix(col, float3(0.02), 1.0 - smoothstep(0.025, 0.04, length(p - float2(float(s) * 0.13, 0.44))));
        float a = inside * in.color.a;
        outc = float4(col * a, a);
    } else if (k > 12.5) {             // seahorse (extra.y: carrying the little letter)
        float2 p = c * float2(0.75, 1.2);
        float d = 1e3;
        d = min(d, length(p - float2(0.05, 0.78)) - 0.17);                                   // head
        float2 sa = float2(0.1, 0.74), sb = float2(0.48, 0.66), pa = p - sa, ba = sb - sa;      // snout
        d = min(d, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.045);
        for (int i = 0; i < 10; i++) {                                                        // curved body
            float t = float(i) / 9.0;
            float2 q = float2(0.14 * sin(t * 3.0 + 0.4) - 0.04, 0.58 - t * 1.15);
            d = min(d, length(p - q) - 0.19 * (1.0 - t * 0.72));
        }
        for (int i = 0; i < 10; i++) {                                                        // curled tail
            float a = float(i) / 9.0 * 4.2;
            float rr = 0.17 * (1.0 - a / 5.2);
            float2 q = float2(0.1, -0.7) + rr * float2(cos(a + 3.3), sin(a + 3.3));
            d = min(d, length(p - q) - (0.05 * (1.0 - a / 5.0) + 0.015));
        }
        float2 fp = (p - float2(-0.2, 0.2)) / float2(0.1 + 0.03 * sin(in.phase * 14.0), 0.16); // flapping fin
        d = min(d, (length(fp) - 1.0) * 0.1);
        float aa = fwidth(d) + 1e-4;
        float inside = 1.0 - smoothstep(-aa, aa, d);
        float3 col = in.color.rgb * (0.75 + 0.35 * (p.y * 0.3 + 0.5));
        col = mix(col, in.color.rgb * 0.6, (1.0 - smoothstep(0.02, 0.05, abs(fract(p.y * 7.0) - 0.5))) * 0.35 * step(p.y, 0.6)); // rings
        col = mix(col, float3(0.02), 1.0 - smoothstep(0.03, 0.045, length(p - float2(0.1, 0.82))));                            // eye
        float a = inside;
        if (in.extra.y > 0.5) {                                                                // little letter on the snout
            float2 cp = p - float2(0.6, 0.6);
            float letter = max(abs(cp.x) - 0.13, abs(cp.y) - 0.09);
            float ci = 1.0 - smoothstep(-aa, aa, letter);
            float3 cc = mix(float3(0.97, 0.95, 0.9), in.color.rgb, step(abs(cp.y + cp.x * 0.7), 0.025) * 0.8);
            col = mix(col, cc, ci);
            a = max(a, ci);
        }
        outc = float4(col * a, a);
    } else if (k > 11.5) {             // pearl: a nacreous sphere resting on the sand, with its shadow; glows when it's new
        float2 pc = (c - float2(0.0, 0.08)) / 0.74;
        float pr = length(pc);
        float aa = fwidth(pr) + 1e-4;
        float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, pr);
        float nz = sqrt(max(0.0, 1.0 - pr * pr));
        float3 n = float3(pc, nz);
        // white nacre with a hint of the project's color, a soft orient shifting with the angle, the water's blue
        // from above and the sand's warmth from below
        float3 nacre = mix(float3(0.93, 0.91, 0.86), in.color.rgb, 0.18);
        float3 orient = 0.5 + 0.5 * cos(6.2831 * (nz * 0.6 + pc.x * 0.2 + in.phase * 0.13 + float3(0.0, 0.33, 0.67)));
        nacre = mix(nacre, nacre * (0.75 + 0.5 * orient), 0.35 * (1.0 - nz * 0.5));
        float diff = clamp(dot(n, normalize(float3(-0.35, 0.75, 0.55))), 0.0, 1.0);
        float3 col = nacre * (0.55 + 0.6 * diff);
        col += float3(0.5, 0.65, 0.75) * smoothstep(0.2, 0.9, pc.y) * (1.0 - nz) * 0.25;
        col += float3(0.45, 0.36, 0.22) * smoothstep(0.1, -0.9, pc.y) * (1.0 - nz) * 0.3;
        float3 hv = normalize(float3(-0.35, 0.75, 0.55) + float3(0.0, 0.0, 1.0));
        col += pow(clamp(dot(n, hv), 0.0, 1.0), 40.0) * 0.9;
        // its shadow on the sand
        float sh = (1.0 - smoothstep(0.0, 0.35, length((c - float2(0.08, -0.7)) / float2(0.85, 0.22)) - 0.6)) * (1.0 - inside);
        float halo = exp(-r * r * 1.5) * in.glow * (1.0 - inside) * 0.8;
        outc = float4(col * inside + in.color.rgb * halo, inside + sh * 0.35 + halo * 0.5);
    } else {                       // aurora: extra.y = shape (0 curtain, 1 band, 2 sunbeam), extra.z = bottom color, extra.w = two colors
        uint pk = uint(in.extra.z + 0.5);
        float3 tintB = float3(float((pk >> 16) & 255u), float((pk >> 8) & 255u), float(pk & 255u)) / 255.0;
        float a, mixB;
        if (in.extra.y > 1.5) {
            // sunbeam: narrow, slanted golden beam
            float x = c.x + c.y * 0.35;
            float band = exp(-pow(x * 3.2, 2.0)) * (0.8 + 0.2 * sin(c.y * 3.0 + in.phase));
            float vfade = smoothstep(-1.0, 0.2, c.y) * (1.0 - smoothstep(0.85, 1.0, c.y));
            a = band * vfade * (1.0 - smoothstep(0.75, 1.0, abs(c.x))) * in.glow * 0.5;
            mixB = 1.0 - smoothstep(-0.8, 0.6, c.y);
        } else if (in.extra.y > 0.5) {
            // wavy horizontal band: sharp top edge, falling downward like a veil
            float center = sin(c.x * 2.4 + in.phase * 0.45) * 0.3 + sin(c.x * 5.5 - in.phase * 0.7) * 0.1;
            float dy = c.y - center;
            float band = exp(-pow(max(dy, 0.0) * 6.0, 2.0)) * exp(-pow(min(dy, 0.0) * 1.8, 2.0));
            // thin irregular fringe (hanging rays), at two frequencies
            float streak = 0.62 + 0.24 * sin(c.x * 150.0 + in.phase * 1.4 + sin(c.x * 11.0 + in.phase * 0.3) * 3.0)
                              + 0.14 * sin(c.x * 37.0 - in.phase * 0.9);
            float hfade = 1.0 - smoothstep(0.55, 1.0, abs(c.x));
            float vfade = 1.0 - smoothstep(0.7, 1.0, abs(c.y));
            a = band * streak * hfade * vfade * in.glow * 0.9;
            mixB = clamp(-dy * 1.4, 0.0, 1.0);
        } else {
            // wavy vertical curtain with streaks
            float wave = sin(c.y * 2.2 + in.phase * 0.5) * 0.25 + sin(c.y * 5.0 - in.phase * 0.8) * 0.07;
            float band = exp(-pow((c.x - wave) * 2.3, 2.0));
            float streak = 0.55 + 0.45 * sin(c.x * 38.0 + in.phase * 1.7 + c.y * 3.0);
            float vfade = smoothstep(-1.0, -0.15, c.y) * (1.0 - smoothstep(0.45, 1.0, c.y));
            float hfade = 1.0 - smoothstep(0.7, 1.0, abs(c.x));
            a = band * streak * vfade * hfade * in.glow * 0.85;
            mixB = 1.0 - smoothstep(-0.8, 0.6, c.y);
        }
        float3 col = in.extra.w > 0.5 ? mix(in.color.rgb, tintB, mixB) : in.color.rgb;
        outc = float4(col * a, a * 0.35);
    }
    // murky water fades what is far away
    outc *= 1.0 - u.turbidity * 0.35;
    outc.rgb = scene_tint(outc.rgb, outc.a, u) * u.grade.rgb;      // water temperature, fog and the hour's color
    Frag2 o;
    o.color = outc;
    // opaque things also cover the glow behind them; a pack's scenery glows only where it's bright (a lantern's window)
    float em = k > 34.5 ? clamp(in.glow, 0.0, 1.0) * smoothstep(0.35, 0.9, max(outc.r, max(outc.g, outc.b)) / max(outc.a, 0.01)) * 0.8
                        : emissive(k, in.glow);
    o.glow = float4(outc.rgb * em, outc.a);
    return o;
}

// ---------- bloom (Renderer): what glows, reduced, blurred and added back ----------

"""#
