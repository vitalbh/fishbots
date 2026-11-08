// Shaders as text, compiled when the app opens (so the project builds with just `swift build`).
// The fish kinds (FishKinds.swift) are inserted at "@fish-kinds"; compile `FishKinds.shaderSource()`, not this.
let shaderBase = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 res;        // size in points
    float time;
    float turbidity;
    float light;
    float alert;
    float2 pix;        // size in pixels
    float2 gaze;      // parallax (mouse), -1…1
    float flash;      // lightning (Scene.swift), 0…1
    float4 grade;     // the hour's color (rgb) and moonlight (w)
    float4 scene;     // continuous controls from gauges: waves, rain, temperature (0.5 neutral), fog
    float4 sky;       // the sun or moon through the surface: x, strength, warmth
};

// Water temperature and fog, applied to everything (background and sprites).
float3 scene_tint(float3 c, float a, constant Uniforms& u) {
    float warm = clamp((u.scene.z - 0.5) * 2.0, 0.0, 1.0), cold = clamp((0.5 - u.scene.z) * 2.0, 0.0, 1.0);
    c = mix(c, c * float3(1.1, 1.0, 0.76) + float3(0.025, 0.015, 0.0) * a, warm * 0.6);
    c = mix(c, c * float3(0.8, 0.95, 1.15), cold * 0.6);
    float3 fogC = float3(0.33, 0.44, 0.5) * (0.4 + 0.6 * u.light);
    return mix(c, fogC * a, u.scene.w * 0.4);
}

// The scene's colors (ThemeUniforms in Theme.swift).
struct Theme {
    float4 deep, shallow, rays, caustics, surface, farWeed, weedLow, weedHigh, sandDark, sandLight, murk;
    float4 params;     // x: seaweed count, y: distant seaweed count, z: rays strength, w: caustics strength
};

struct Sprite {
    float2 pos;
    float2 dir;
    float size;
    float kind;        // 0 fish, 1 bubble, 2 ring, 3 food, 4 sparkle, 5 jellyfish
    float glow;
    float phase;
    float4 color;
    float4 extra;      // x: vertical mirror (fish), y: stripes
    float4 aux;        // fish: where the eye looks (xy) and blur by distance (z)
};

// ---------- background ----------

struct BgOut { float4 position [[position]]; };

// Two targets: the image, and what glows (blurred into the bloom afterwards; see Renderer).
struct Frag2 { float4 color [[color(0)]]; float4 glow [[color(1)]]; };

vertex BgOut bg_vertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    BgOut o;
    o.position = float4(p[vid], 0, 1);
    return o;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float caustic(float2 p, float t) {
    float2 i = p;
    float c = 1.0;
    float intensity = 0.005;
    for (int n = 0; n < 4; n++) {
        float tt = t * (1.0 - (3.5 / float(n + 1)));
        i = p + float2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
        c += 1.0 / length(float2(p.x / (sin(i.x + tt) / intensity), p.y / (cos(i.y + tt) / intensity)));
    }
    c /= 4.0;
    c = 1.17 - pow(c, 1.4);
    return pow(abs(c), 8.0);
}

// weeds[k]: x (0…1), height (0…1), bend (how far the tip is pushed, in widths), kind (0 blade, 1 kelp, 2 leafy).
// From Tank.weedUniforms.
fragment Frag2 bg_fragment(BgOut in [[stage_in]], constant Uniforms& u [[buffer(0)]], constant Theme& th [[buffer(1)]],
                            constant float4* weeds [[buffer(2)]]) {
    float2 uv = float2(in.position.x / u.pix.x, 1.0 - in.position.y / u.pix.y);
    float aspect = u.res.x / u.res.y;
    float t = u.time;
    float L = u.light;

    float3 deep = th.deep.rgb;
    float3 shallow = th.shallow.rgb;
    float3 col = mix(deep, shallow, pow(uv.y, 1.3)) * (0.5 + 0.5 * L);

    float2 q = float2(uv.x * aspect, uv.y);
    // refraction: near the surface the light wobbles, as if through little waves (more with the waves gauge)
    q += float2(sin(uv.y * 70.0 + t * 2.1 + uv.x * 9.0), cos(uv.x * 55.0 * aspect - t * 1.7))
         * 0.0035 * (1.0 + 2.0 * u.scene.x) * smoothstep(0.7, 0.96, uv.y);

    // light rays coming from the surface
    float r1 = sin((q.x + q.y * 0.35) * 9.0 + t * 0.25) * 0.5 + 0.5;
    float r2 = sin((q.x - q.y * 0.20) * 15.0 - t * 0.17) * 0.5 + 0.5;
    float rays = pow(r1 * r2, 3.0) * smoothstep(0.1, 1.0, uv.y);
    // broad, slow beams under the narrow ones (they light up the marine snow too: Tank.rayLight)
    float broad = pow(sin((q.x + q.y * 0.5) * 3.1 + t * 0.05) * 0.5 + 0.5, 6.0) * smoothstep(0.25, 1.0, uv.y);
    rays += broad * 0.45;
    float3 rayC = mix(th.rays.rgb, float3(0.55, 0.7, 1.0), u.grade.w);      // at night, moonlight
    col += rayC * rays * th.params.z * max(L, u.grade.w * 0.8);

    // the sun (or the moon) seen through the surface: a soft bright spot just under it, with a halo
    {
        float2 sd = float2((uv.x - u.sky.x) * aspect, (uv.y - 0.93) * 2.2);
        float spot = exp(-dot(sd, sd) * 160.0) + exp(-dot(sd, sd) * 18.0) * 0.35;
        float3 sunC = mix(float3(0.65, 0.78, 1.0), float3(1.0, 0.82, 0.55), u.sky.z);
        col += sunC * spot * u.sky.y;
    }

    // caustics
    float c = clamp(caustic(float2(q.x, q.y * 1.5) * 5.0 - 250.0, t * 0.35), 0.0, 1.0);
    col += th.caustics.rgb * c * th.params.w * (0.3 + uv.y) * L;

    // water surface
    float waves = u.scene.x;
    float surf = 0.965 + (0.006 * sin(uv.x * 30.0 + t * 1.5) + 0.004 * sin(uv.x * 71.0 - t * 2.3)) * (1.0 + 2.5 * waves)
               + 0.007 * waves * sin(uv.x * 13.0 - t * 3.1) - 0.004 * waves;
    if (uv.y > surf) {
        col = mix(col, th.surface.rgb * (0.4 + 0.6 * L), 0.55);
        // the sky above the water: orange with a low sun, dark blue with stars at night
        col = mix(col, float3(1.0, 0.58, 0.32) * 0.55, u.sky.z * u.sky.y * 1.4);
        if (u.grade.w > 0.05) {
            col = mix(col, float3(0.04, 0.06, 0.16), u.grade.w * 0.5);
            float2 sc = floor(float2(uv.x * aspect * 260.0, uv.y * 140.0));
            float star = step(0.993, hash21(sc)) * (0.55 + 0.45 * sin(t * (1.5 + hash21(sc + 3.1) * 3.0) + hash21(sc) * 40.0));
            col += float3(0.85, 0.9, 1.0) * star * u.grade.w * 0.8;
        }
        // rain: short falling streaks in the air above the water
        float rain = u.scene.y;
        if (rain > 0.01) {
            // thin slanted streaks: columns of cells, each with a short dash that falls through it
            float2 rp = float2((uv.x + uv.y * 0.12) * aspect * 220.0, uv.y * 26.0);
            float colId = floor(rp.x);
            float hcol = hash21(float2(colId, 3.7));
            float y = rp.y + t * (10.0 + hcol * 5.0) + hcol * 40.0;
            float on = step(1.0 - rain * 0.16, hash21(float2(colId, floor(y))));
            float thin = 1.0 - smoothstep(0.06, 0.16, abs(fract(rp.x) - 0.5));
            float dash = smoothstep(0.0, 0.15, fract(y)) * (1.0 - smoothstep(0.45, 0.6, fract(y)));
            col += float3(0.75, 0.85, 0.9) * on * thin * dash * 0.45 * (0.5 + 0.5 * L);
        }
    }
    col *= 1.0 - u.scene.y * 0.18;                                       // a rainy day is a darker day
    float surfLine = (1.0 - smoothstep(0.0, 0.004, abs(uv.y - surf))) * 0.35 * L;
    // glints running along the underside of the surface
    float glint = pow(max(0.0, sin(uv.x * 140.0 + t * 1.7) * sin(uv.x * 57.0 - t * 1.1)), 12.0)
                * (1.0 - smoothstep(0.0, 0.012, surf - uv.y)) * step(uv.y, surf) * L;
    surfLine += glint * 0.8;
    col += float3(0.6, 0.85, 0.9) * surfLine;
    // what glows in the background: the sun rays (a little) and the bright line of the surface
    float3 glowBg = rayC * rays * th.params.z * L * 0.5 + float3(0.6, 0.85, 0.9) * surfLine * 0.6;
    {
        float2 sd = float2((uv.x - u.sky.x) * aspect, (uv.y - 0.93) * 2.2);
        glowBg += mix(float3(0.65, 0.78, 1.0), float3(1.0, 0.82, 0.55), u.sky.z) * exp(-dot(sd, sd) * 160.0) * u.sky.y * 0.8;
    }

    // in the distance: rocks and seaweed faded by the water (barely move with parallax)
    float3 fog = mix(deep, shallow, 0.35) * (0.55 + 0.45 * L);
    float ux = uv.x + u.gaze.x * 0.006;
    float pebbles = 0.1 + 0.05 * vnoise(float2(ux * 7.0, 1.3)) + 0.035 * vnoise(float2(ux * 19.0, 4.1));
    if (uv.y < pebbles) col = mix(col, fog * 0.75, 0.55 * (1.0 - smoothstep(pebbles - 0.012, pebbles, uv.y) * 0.4));
    // a distant reef: soft silhouettes of rock and coral far away in the haze, higher in two outcrops (barely any parallax)
    if (uv.y < 0.37) {                                                   // (the reef never goes higher: skip the noise above it)
        float rx = uv.x + u.gaze.x * 0.003;
        float ridge = 0.12 + 0.1 * vnoise(float2(rx * 4.0, 2.7)) + 0.05 * vnoise(float2(rx * 13.0, 5.3));
        ridge += 0.09 * smoothstep(0.17, 0.0, abs(rx - 0.24)) + 0.07 * smoothstep(0.2, 0.0, abs(rx - 0.8));
        if (uv.y < ridge) {
            col = mix(col, fog * 0.52, 0.6 * (0.75 + 0.25 * smoothstep(ridge - 0.1, ridge, uv.y)));
            col += fog * 0.18 * (1.0 - smoothstep(0.0, 0.006, ridge - uv.y)) * L;     // its top catches a little light
        }
    }
    int farCount = int(th.params.y + 0.5);
    for (int k = 0; k < farCount; k++) {
        float fk = float(k) + 20.0;
        float x0 = fract(sin(fk * 57.3) * 913.7) * 0.96 + 0.02;
        if (abs(ux - x0) > 0.03) continue;                       // far from this blade: skip it (most pixels)
        float hgt = 0.12 + fract(sin(fk * 7.7) * 61.3) * 0.2;
        float base = 0.075 + 0.018 * sin(x0 * 7.0 + 1.3) + 0.008 * sin(x0 * 23.0) - 0.012;   // starts inside the sand
        float yy = uv.y - base;
        if (yy > 0.0 && yy < hgt) {
            float k01 = yy / hgt;
            float sway = sin(yy * 9.0 - t * 0.8 + fk) * 0.008 * k01;
            float dx = (ux - x0 - sway) * aspect;
            float w = 0.005 * (1.0 - 0.7 * k01);
            float blade = 1.0 - smoothstep(w * 0.4, w * 1.3, abs(dx));
            col = mix(col, mix(fog, th.farWeed.rgb, 0.35), blade * 0.5);
        }
    }

    // seaweed
    int weedCount = int(th.params.x + 0.5);
    for (int k = 0; k < weedCount; k++) {
        float fk = float(k);
        float x0 = weeds[k].x;
        // far from this blade: skip it (leafy stems reach a little wider than blades and kelp)
        if (abs(uv.x + u.gaze.x * 0.012 - x0) > (weeds[k].w > 1.5 ? 0.045 : 0.035) + abs(weeds[k].z)) continue;
        float hgt = weeds[k].y;
        float yy = uv.y - (0.075 + 0.018 * sin(x0 * 7.0 + 1.3) + 0.008 * sin(x0 * 23.0) - 0.015);
        if (yy > 0.0 && yy < hgt) {
            float k01 = yy / hgt;
            float sway = sin(yy * 11.0 - t * 1.1 + fk * 1.7) * 0.014 * k01 + sin(t * 0.4 + fk) * 0.01 * k01 * k01
                       + weeds[k].z * pow(k01, 1.5);                       // pushed aside by a fish going through
            float dx = (uv.x + u.gaze.x * 0.012 - x0 - sway) * aspect;
            int kind = int(weeds[k].w + 0.5);
            float3 green = mix(th.weedLow.rgb, th.weedHigh.rgb, k01) * (0.45 + 0.55 * L);
            // each blade its own shade: a little yellower, bluer or darker than the theme's
            float hv = fract(sin(fk * 17.31) * 4375.85);
            green *= mix(float3(1.08, 1.05, 0.82), float3(0.86, 1.0, 1.12), hv) * (0.85 + 0.3 * fract(hv * 7.3));
            float blade;
            if (kind == 1) {
                // kelp: a wide ribbon with rippling edges and a darker midrib, a little browner
                float w = 0.017 * (1.0 - 0.45 * k01) * (0.85 + 0.15 * sin(yy * 95.0 + t * 2.0 + fk));
                blade = 1.0 - smoothstep(w * 0.75, w, abs(dx));
                green = mix(green, float3(0.42, 0.36, 0.14) * (0.45 + 0.55 * L), 0.35);
                float xn = clamp(dx / w, -1.0, 1.0);
                green *= 0.72 + 0.4 * sqrt(1.0 - xn * xn);                           // rounded across: the middle bulges
                green *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, w * 0.18, abs(dx)));
                green *= 0.85 + 0.15 * smoothstep(-w, w, dx);                       // one side catches the light
                green *= 1.0 + 0.1 * sin(yy * 160.0 + fk);                           // faint wrinkles along it
                // gas bladders that keep it afloat, at the base of the ribbon, alternating sides
                float bs = 0.06, bc = floor(yy / bs), bsd = fmod(bc, 2.0) < 0.5 ? 1.0 : -1.0;
                float2 bq = float2(dx - bsd * w * 0.95, (fract(yy / bs) - 0.5) * bs) / float2(0.0065, 0.0075);
                float bl = (1.0 - smoothstep(0.8, 1.0, length(bq))) * step(0.08, k01) * step(k01, 0.9);
                green = mix(green, mix(float3(0.55, 0.5, 0.2), th.weedHigh.rgb, 0.4) * (0.5 + 0.5 * L) * (0.8 + 0.4 * smoothstep(-0.8, 0.8, bq.y - bq.x * 0.3)), bl);
                blade = max(blade, bl);
            } else if (kind == 2) {
                // a thin stem with small oval leaves on alternating sides
                float stem = 1.0 - smoothstep(0.0015, 0.003, abs(dx));
                float spacing = 0.032;
                float cell = floor(yy / spacing);
                float side = fmod(cell, 2.0) < 0.5 ? 1.0 : -1.0;
                float2 lp = float2(dx - side * 0.011, (fract(yy / spacing) - 0.5) * spacing);
                float ang = side * 0.5;
                lp = float2(lp.x * cos(ang) - lp.y * sin(ang), lp.x * sin(ang) + lp.y * cos(ang));
                float2 ln = lp / float2(0.012, 0.0065);
                float leaf = (1.0 - smoothstep(0.85, 1.0, length(ln))) * step(0.04, k01) * step(k01, 0.97);
                blade = max(stem, leaf);
                // each leaf: lighter along its vein, darker at the edges, one half in shade
                float shade = (0.75 + 0.35 * (1.0 - abs(ln.y))) * (0.88 + 0.12 * sign(ln.y));
                float vein = (1.0 - smoothstep(0.0, 0.18, abs(ln.y))) * step(abs(ln.x), 0.8);
                green = mix(green, (green * 1.25 + 0.03) * shade + green * vein * 0.25, leaf * 0.85);
                green *= 1.0 - stem * (1.0 - leaf) * 0.25;
            } else {
                // a flat blade that turns as it rises: narrow and darker where it's seen edge-on
                float tw = sin(yy * 16.0 + fk * 2.3 + t * 0.5);
                float w = 0.009 * (1.0 - 0.75 * k01) * (0.4 + 0.6 * abs(tw));
                blade = 1.0 - smoothstep(w * 0.5, w, abs(dx));
                float xn = clamp(dx / w, -1.0, 1.0);
                green *= (0.7 + 0.3 * abs(tw)) * (0.8 + 0.3 * sqrt(1.0 - xn * xn)) * (1.0 + 0.14 * xn * sign(tw));
                green = mix(green, green * 1.3 + 0.02, (1.0 - smoothstep(0.0, 0.15, abs(xn))) * 0.35);   // midrib
            }
            // darker down in the sand's shadow, and the tips glow a little with the light passing through them
            green *= 0.55 + 0.45 * smoothstep(0.0, 0.25, k01);
            green += th.weedHigh.rgb * smoothstep(0.55, 1.0, k01) * 0.12 * L;
            green *= mix(float3(1.0), float3(1.2, 0.82, 0.62), u.sky.z * u.sky.y * 2.2);   // reddish in the sunset
            green *= 1.0 - u.grade.w * 0.3;                                              // darker at night
            col = mix(col, green, blade * 0.9);
        }
    }

    // sand: a floor seen at a slant, so its texture shrinks toward the back line (floor coordinates fp)
    float sandH = 0.075 + 0.018 * sin(uv.x * 7.0 + 1.3) + 0.008 * sin(uv.x * 23.0);
    if (uv.y < sandH) {
        float depth = clamp(uv.y / sandH, 0.0, 1.0);                    // 0 at the front, 1 at the back line
        float persp = mix(1.0, 0.2, depth);
        float2 fp = float2((uv.x - 0.5) * aspect / persp, 1.0 / persp);
        float2 fq = float2(fp.x, fp.y * 0.12);                            // the same, with square cells on screen up front
        // patches of lighter and darker sand, and the color between the theme's two sands
        float g = vnoise(fq * 4.0) * 0.55 + vnoise(fq * 13.0) * 0.3 + vnoise(fq * 40.0) * 0.15;
        float3 sand = mix(th.sandDark.rgb, th.sandLight.rgb, smoothstep(0.2, 0.85, g)) * (0.4 + 0.6 * L);
        // ripples shaped by the current: crests across the floor, bent by noise, lit on the side facing the surface;
        // they fade where they'd get finer than a pixel
        float ph = fp.y * 55.0 + fp.x * 6.0 + vnoise(fp * float2(2.5, 1.5)) * 9.0;
        float ripA = (1.0 - smoothstep(0.6, 1.6, fwidth(ph))) * (0.6 + 0.4 * vnoise(fp * 2.0 + 7.0));
        float rs = ph + 0.6 * sin(ph);                                    // a steeper side and a gentler one
        sand *= 1.0 + ripA * (0.11 * sin(rs) - 0.07 * cos(rs));
        // pebbles and bits of shell scattered on it, each with a little shadow below
        float2 cellP = fq * 30.0;
        float2 cid = floor(cellP);
        float hr = hash21(cid);
        if (hr > 0.76) {
            float2 ctr = float2(hash21(cid + 3.1), hash21(cid + 7.7)) * 0.6 + 0.2;
            float2 pq = (fract(cellP) - ctr) / float2(1.0, 0.7);
            float rad = 0.1 + 0.16 * hash21(cid + 1.9);
            float pd = length(pq) - rad;
            float pa = 1.0 - smoothstep(-fwidth(pd), fwidth(pd), pd);
            float tone = hash21(cid + 5.3);
            float3 pc = (tone < 0.5 ? th.sandDark.rgb * mix(0.4, 0.75, tone * 2.0) : th.sandLight.rgb * 1.45 + 0.07) * (0.4 + 0.6 * L);
            pc *= 0.8 + 0.45 * smoothstep(-rad, rad, pq.y);                 // lit from above
            float sh = (1.0 - smoothstep(0.0, rad * 0.6, length((pq - float2(0.03, -0.06)) / float2(1.2, 0.7)) - rad));
            sand *= 1.0 - sh * 0.4 * (1.0 - pa);
            sand = mix(sand, pc, pa * (1.0 - smoothstep(0.75, 1.0, depth)));
        }
        // fine grains glinting in the light
        float grain = hash21(floor(in.position.xy * 0.5));
        sand *= 0.95 + 0.1 * grain;
        sand += th.sandLight.rgb * step(0.997, grain) * 0.35 * L * (0.5 + 0.5 * sin(t * 2.0 + grain * 900.0));
        // the caustics play on it, stretched by the slant
        float cs = clamp(caustic(fq * float2(6.0, 9.0) - 120.0, t * 0.35), 0.0, 1.0);
        sand += float3(0.6, 0.7, 0.6) * mix(c, cs, 0.7) * (0.12 + 0.22 * u.sky.y * (1.0 - u.grade.w)) * L;   // stronger under a high sun
        // darker toward the glass, hazier toward the back, and the back line catches a little light
        sand *= mix(0.62, 1.0, smoothstep(0.0, 0.7, depth));
        sand = mix(sand, fog * 0.9, depth * depth * 0.35);
        sand += th.sandLight.rgb * (1.0 - smoothstep(0.0, 0.006, sandH - uv.y)) * 0.12 * L;
        float edge = smoothstep(sandH - 0.004, sandH, uv.y);
        col = mix(sand, col, edge);
    }

    // murky water
    col = mix(col, th.murk.rgb * (0.45 + 0.55 * L), u.turbidity * 0.7);

    // glass: vignette, reflection and alert at the edges
    float2 d = (uv - 0.5) * float2(1.1, 1.3);
    float vig = clamp(1.0 - dot(d, d) * 1.1, 0.0, 1.0);
    col *= 0.35 + 0.65 * vig;
    col += (1.0 - smoothstep(0.0, 0.03, abs((uv.x * 0.6 + uv.y) - 1.25))) * 0.035;
    col += float3(0.6, 0.06, 0.05) * u.alert * (1.0 - vig) * 0.9;
    // lightning: a cold flash, stronger near the surface
    col += float3(0.55, 0.65, 0.85) * u.flash * (0.45 + 0.55 * uv.y);

    col = scene_tint(col, 1.0, u);
    Frag2 o;
    o.color = float4(col * u.grade.rgb, 1.0);
    o.glow = float4(glowBg * u.grade.rgb * (1.0 - u.turbidity * 0.7), 1.0);
    return o;
}

// ---------- sprites (fish, bubbles, rings…) ----------

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

vertex SpOut sprite_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device Sprite* sp [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
    float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
    Sprite s = sp[iid];
    float2 c = corners[vid];
    float2 ext;
    if (s.kind < 0.5) ext = float2(1.25, 0.8) * s.size * (int(s.extra.z + 0.5) == LANTERN_KIND ? LANTERN_ROOM : 1.0); // the lanternfish: room for its light
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
    float R = r / max(se, 1e-3);
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

// old battery lying in the sand: glow = charge (0…1), extra.y = plugged in.
// The part below the sand line disappears (stays buried).
float4 draw_battery(float2 c, float level, float phase, float4 extra, float2 world, float2 res) {
    float2 p = c * float2(1.2, 0.6);
    float body = sd_box(p - float2(-0.05, 0.0), float2(0.92, 0.42), 0.14);
    float cap = sd_box(p - float2(0.97, 0.0), float2(0.1, 0.17), 0.04);
    float d = min(body, cap);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    // faded casing with rust
    float rust = vnoise(p * 9.0 + 3.1) * vnoise(p * 23.0);
    float3 shell = p.x > 0.35 ? float3(0.50, 0.34, 0.16) : float3(0.13, 0.13, 0.12);
    shell = mix(shell, float3(0.40, 0.22, 0.10), smoothstep(0.25, 0.55, rust) * 0.8);
    if (cap < 0.0) shell = float3(0.45, 0.43, 0.38);
    shell *= 0.7 + 0.4 * (p.y + 0.42);
    float3 col = shell;

    // single-color little window: the color alone tells the charge
    float window = sd_box(p - float2(-0.12, 0.02), float2(0.55, 0.16), 0.08);
    float3 tint = level < 0.2 ? float3(1.0, 0.28, 0.22) : level < 0.5 ? float3(1.0, 0.78, 0.25) : float3(0.35, 0.95, 0.45);
    float blink = level < 0.2 ? 0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 5.0)) : 1.0;
    float bright = extra.y > 0.5 ? 0.8 + 0.2 * sin(phase * 3.0) : 0.7;
    col = mix(col, tint * bright * blink, 1.0 - smoothstep(-aa, aa, window));

    // buried: disappears below the sand and darkens near it (contact shadow)
    float ux = world.x / res.x;
    float sandY = (0.075 + 0.018 * sin(ux * 7.0 + 1.3) + 0.008 * sin(ux * 23.0)) * res.y;
    float aboveSand = smoothstep(sandY - 1.0, sandY + 1.0, world.y);
    col *= mix(0.45, 1.0, smoothstep(sandY, sandY + 7.0, world.y));
    inside *= aboveSand;

    float halo = 0.0;
    if (extra.y > 0.5) halo = exp(-max(d, 0.0) * 22.0) * (0.18 + 0.1 * sin(phase * 3.0)) * (1.0 - inside) * aboveSand
                              * (1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y))));
    return float4(col * inside + tint * halo, inside + halo * 0.5);
}

// ---------- scenery on the sand (rock, shell, chest); col is already lit ----------

// one stone of a rock: a lumpy ellipse; returns its distance (x) and a dome normal (yzw)
float4 rock_blob(float2 c, float2 at, float2 rad, float seed) {
    float2 q = (c - at) / rad;
    float ang = atan2(q.y, q.x);
    float wob = 1.0 + 0.07 * sin(ang * 3.0 + seed * 5.0) + 0.04 * sin(ang * 5.0 + seed * 11.0) + 0.025 * sin(ang * 9.0 + seed * 3.0);
    float l = length(q);
    float d = (l - wob) * min(rad.x, rad.y);
    float2 qn = q / wob;
    float3 n = normalize(float3(qn * 1.1, sqrt(max(0.02, 1.0 - dot(qn, qn)))));
    return float4(d, n);
}

float4 draw_rock(float2 c, float phase, float4 col) {
    float seed = phase;
    float side = fract(seed * 0.73) < 0.5 ? -1.0 : 1.0;          // which side the smaller stone leans on
    float4 b1 = rock_blob(c, float2(-0.1 * side, -0.16), float2(0.74, 0.76), seed);
    float4 b2 = rock_blob(c, float2(0.55 * side, -0.4), float2(0.38, 0.36), seed + 1.3);
    float4 b3 = rock_blob(c, float2(-0.68 * side, -0.52), float2(0.2, 0.13), seed + 2.1);   // a pebble
    float d12 = smin_k(b1.x, b2.x, 0.06);
    float d = min(d12, b3.x);
    d = max(d, -(c.y + 0.6));                                        // flat bottom, sunk in the sand
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 n = b1.x < b2.x ? b1.yzw : b2.yzw;
    if (b3.x < min(b1.x, b2.x)) n = b3.yzw;
    float crease = 1.0 - smoothstep(0.0, 0.05, min(b1.x, b2.x) - d12);  // where the two stones meet

    // a rough surface: the noise bends the normal a little
    float2 tp = c * 7.0 + seed * 13.0;
    float h0 = vnoise(tp), hx = vnoise(tp + float2(0.15, 0.0)), hy = vnoise(tp + float2(0.0, 0.15));
    n = normalize(n + float3(h0 - hx, h0 - hy, 0.0) * 0.7);
    float3 L = normalize(float3(-0.35, 0.85, 0.5));
    float diff = clamp(dot(n, L), 0.0, 1.0);
    float spec = pow(clamp(dot(reflect(-L, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 18.0);

    float fine = vnoise(c * 23.0 + seed * 7.0);
    float3 alb = col.rgb * (0.82 + 0.3 * vnoise(c * 3.0 + seed * 4.0)) * (0.9 + 0.2 * fine);
    alb *= 1.0 + 0.08 * sin(c.y * 22.0 + vnoise(c * 4.0 + seed) * 4.0);               // faint layers in the stone
    // speckles: little light and dark grains
    float g = hash21(floor(c * 60.0 + seed * 17.0));
    alb = mix(alb, alb * 1.3 + 0.03, step(0.96, g) * 0.4);
    alb = mix(alb, alb * 0.6, step(g, 0.03) * 0.4);
    // cracks: thin dark lines where the noise crosses its middle
    float cr = abs(vnoise(c * 4.5 + seed * 9.0 + float2(vnoise(c * 9.0) * 0.6)) - 0.5);
    float crack = (1.0 - smoothstep(0.0, 0.02, cr)) * smoothstep(0.45, 0.7, vnoise(c * 2.0 + seed * 3.0));

    float3 c3 = alb * (float3(0.3, 0.36, 0.42) + float3(1.05, 1.0, 0.92) * diff) + float3(0.8, 0.9, 1.0) * spec * 0.1;
    c3 *= 1.0 - crack * 0.45;
    c3 *= 1.0 - crease * 0.4;
    // moss and algae on what faces up, with a ragged edge
    float up = n.y * 0.7 + (c.y + 0.6) * 0.35;
    float moss = smoothstep(0.7, 0.86, up + (vnoise(c * 9.0 + seed * 5.0) - 0.5) * 0.45);
    float3 mossC = mix(float3(0.3, 0.42, 0.26), col.rgb, 0.3) * (0.6 + 0.6 * diff) * (0.8 + 0.4 * fine) * (0.7 + dot(col.rgb, float3(0.3)));
    c3 = mix(c3, mossC, moss * 0.6);
    // the sand: darker where the stone sinks into it (ambient occlusion)
    c3 *= 0.55 + 0.45 * smoothstep(-0.62, -0.35, c.y);
    // the edge catches the light from above
    float edge = 1.0 - smoothstep(0.0, 0.04, -d);
    c3 += float3(0.7, 0.85, 0.95) * edge * clamp(n.y, 0.0, 1.0) * 0.18 * col.rgb * 2.0;
    return float4(c3 * a, a);
}

float4 draw_shell(float2 c, float phase, float4 col) {
    float2 p = c - float2(0.0, -0.62);
    float th = atan2(p.x, p.y);                                       // 0 = straight up from the hinge
    float r = length(p);
    float edge = 1.3 + 0.06 * cos(th * 13.0);                         // scalloped rim
    float fan = max((r - edge) * 0.8, (abs(th) - 1.12) * 0.6);
    float ears = sd_box(p - float2(0.0, 0.06), float2(0.34, 0.1), 0.03);
    float d = max(min(fan, ears), -(c.y + 0.72));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float ribs = 0.5 + 0.5 * cos(th * 13.0);
    float3 base = col.rgb * (0.68 + 0.32 * ribs) * (0.72 + 0.38 * clamp(r / 1.3, 0.0, 1.0));
    base += col.rgb * pow(ribs, 6.0) * 0.25 * smoothstep(0.3, 1.2, r);   // nacre sheen on the ribs
    return float4(base * a, a);
}

// the oyster (the big shell of the scenery): a rough, lumpy shell lying on the sand, a little open now and then,
// with a pearl peeking out of the gap. t: time.
float4 draw_oyster(float2 c, float t, float4 col) {
    float open = 0.05 + 0.06 * smoothstep(0.3, 1.0, sin(t * 0.21));
    float xn = c.x / 0.84;
    float wav = 0.035 * sin(c.x * 17.0 + 1.0) + 0.02 * sin(c.x * 37.0 + 2.0);       // the frilly lip
    float rimL = -0.36 + wav;
    float rimU = rimL + open * max(0.0, 1.0 - xn * xn) + 0.01;
    // the valves: a lumpy dome on top (lifted by `open`) and a shallow bowl below
    float lump = 0.09 * vnoise(c * 3.5 + 3.0) + 0.03 * vnoise(c * 11.0);
    float2 uq = (c - float2(0.04, rimU - 0.02)) / float2(0.8 + lump, 0.62 + lump);
    float upper = max(length(uq) - 1.0, rimU - c.y);
    float2 lq = (c - float2(0.0, rimL + 0.02)) / float2(0.88 + lump, 0.3);
    float lower = max(length(lq) - 1.0, c.y - rimL);
    float gapIn = max(length((c - float2(0.0, -0.36)) / float2(0.82, 0.4)) - 1.0, max(c.y - rimU, rimL - c.y));
    float shellD = min(min(upper, lower), gapIn);
    float d = max(shellD, -(c.y + 0.72));                                              // half sunk in the sand
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float3 L3 = normalize(float3(-0.3, 0.85, 0.45));
    float3 c3;
    if (upper <= 0.0) {
        // the top valve: growth lines parallel to the lip, ribs from the hinge, rough and a little purple at the lip
        float topY = rimU - 0.02 + (0.62 + lump) * sqrt(max(0.0, 1.0 - uq.x * uq.x));
        float v = clamp((c.y - rimU) / max(topY - rimU, 0.01), 0.0, 1.0);
        float3 n = normalize(float3(uq.x, uq.y, sqrt(max(0.02, 1.0 - dot(uq, uq)))));
        float2 tp = c * 9.0;
        float h0 = vnoise(tp), hx = vnoise(tp + float2(0.2, 0.0)), hy = vnoise(tp + float2(0.0, 0.2));
        n = normalize(n + float3(h0 - hx, h0 - hy, 0.0) * 1.2);
        float diff = clamp(dot(n, L3), 0.0, 1.0);
        float growth = 0.5 + 0.5 * sin(v * 22.0 + vnoise(c * 3.0) * 7.0 + vnoise(c * 9.0) * 2.0);
        float ribs = 0.5 + 0.5 * sin(atan2(c.x, 0.2 - c.y) * 16.0 + vnoise(c * 4.0) * 2.0);
        float3 alb = base * (0.86 + 0.14 * growth) * (0.88 + 0.14 * ribs) * (0.85 + 0.3 * vnoise(c * 3.0 + 1.0));
        alb = mix(alb, alb * float3(0.85, 0.72, 0.9), (1.0 - smoothstep(0.0, 0.3, v)) * 0.6);     // purplish near the lip
        // a few barnacles and specks of algae
        float2 bc = floor(c * 7.0);
        float2 bp = fract(c * 7.0) - 0.5 - (float2(hash21(bc), hash21(bc + 4.0)) - 0.5) * 0.5;
        float bar = step(0.9, hash21(bc + 9.0)) * (1.0 - smoothstep(0.1, 0.16, length(bp))) * step(0.25, v);
        alb = mix(alb, base * 1.25 + 0.08, bar * 0.7);
        alb = mix(alb, float3(0.3, 0.42, 0.28) * dot(base, float3(0.6)), smoothstep(0.6, 0.85, vnoise(c * 4.0 + 7.0)) * smoothstep(0.4, 0.9, v) * 0.5);
        c3 = alb * (float3(0.32, 0.36, 0.42) + float3(1.0, 0.97, 0.9) * diff);
        c3 += float3(0.8, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.04, -upper)) * smoothstep(0.3, 1.0, v) * 0.15;   // rim light
        c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.035, c.y - rimU)) * 0.3;                         // the lip's edge
    } else if (lower <= 0.0) {
        // the bottom valve: mostly in shade, with vertical ribs
        float ribs = 0.5 + 0.5 * sin(c.x * 26.0 + vnoise(c * 5.0) * 2.0);
        c3 = base * (0.42 + 0.14 * ribs) * (0.8 + 0.3 * vnoise(c * 8.0)) * (0.7 + 0.5 * smoothstep(-0.7, rimL, c.y));
        c3 = mix(c3, base * 0.85 + 0.12, (1.0 - smoothstep(0.0, 0.03, rimL - c.y)) * 0.6);    // its lip catches the light
    } else {
        // the gap: dark inside, a gleam of nacre along the lips, and the pearl
        float g = clamp((c.y - rimL) / max(rimU - rimL, 0.005), 0.0, 1.0);
        float3 nacre = 0.7 + 0.3 * cos(6.2831 * (c.x * 1.5 + float3(0.0, 0.33, 0.67)));
        c3 = mix(base * 0.08, nacre * 0.55, pow(1.0 - g, 3.0) * 0.8 + pow(g, 4.0) * 0.3);
        float2 pp = (c - float2(0.08, rimL + 0.035)) / 0.075;
        float pr = length(pp);
        if (pr < 1.0) {
            float nz = sqrt(1.0 - pr * pr);
            float3 pc = float3(0.95, 0.92, 0.86) * (0.45 + 0.55 * nz) + 0.6 * exp(-dot(pp - float2(-0.35, 0.4), pp - float2(-0.35, 0.4)) * 6.0);
            c3 = mix(c3, pc, 1.0 - smoothstep(0.85, 1.0, pr));
        }
    }
    c3 *= 0.6 + 0.4 * smoothstep(-0.74, -0.5, c.y);                                    // shadowed where it meets the sand
    return float4(c3 * a, a);
}

// distance to the nearest border between voronoi cells (for lace and meshes)
float vor_edge(float2 x) {
    float2 n = floor(x), f = fract(x), mr = float2(0.0), mg = float2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float2 g = float2(i, j), o = float2(hash21(n + g), hash21(n + g + 17.3));
        float2 r = g + o - f;
        float dd = dot(r, r);
        if (dd < md) { md = dd; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
        float2 g = mg + float2(i, j), o = float2(hash21(n + g), hash21(n + g + 17.3));
        float2 r = g + o - f;
        if (dot(mr - r, mr - r) > 1e-5) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
    }
    return md;
}

// turtle in profile, facing +x: a domed shell of plates, a pale belly, a beaked head and long flippers that row
float4 draw_turtle(float2 c, float phase, float4 col) {
    float2 p = c * float2(1.3, 0.9);
    float paddle = sin(phase * 2.2);
    // shell: a dome, its plates the cells of a voronoi on its surface, a ring of small plates along the rim
    float2 sq = (p - float2(-0.02, -0.04)) / float2(0.62, 0.42);
    float carapace = max(length(sq) - 1.0, -(sq.y + 0.12)) * 0.38;
    float bellyD = max(length((p - float2(0.0, -0.06)) / float2(0.6, 0.15)) - 1.0, p.y + 0.03) * 0.14;
    // head and neck, and the flippers: tapered, curved paddles hinged at the shoulder and the hip
    float headD = length((p - float2(0.76, 0.02)) / float2(0.19, 0.13)) - 1.0;
    headD *= 0.13;
    float2 n0 = float2(0.45, -0.02), n1 = float2(0.66, 0.01), pa = p - n0, ba = n1 - n0;
    float neck = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - 0.085;
    float fang = -0.95 + paddle * 0.45;
    float2 fq = p - float2(0.3, -0.1);
    fq = float2(fq.x * cos(fang) + fq.y * sin(fang), -fq.x * sin(fang) + fq.y * cos(fang));
    float ft = clamp(fq.x / 0.62, 0.0, 1.0);
    float front = max(abs(fq.y - 0.06 * sin(ft * 3.1416)) - 0.075 * (1.0 - ft * 0.8), -fq.x);
    front = max(front, fq.x - 0.62);
    float bang = -2.6 - paddle * 0.25;
    float2 bq = p - float2(-0.42, -0.1);
    bq = float2(bq.x * cos(bang) + bq.y * sin(bang), -bq.x * sin(bang) + bq.y * cos(bang));
    float bt = clamp(bq.x / 0.3, 0.0, 1.0);
    float back = max(max(abs(bq.y) - 0.07 * (1.0 - bt * 0.6), -bq.x), bq.x - 0.3);
    float skin = min(min(headD, neck), min(front, back));
    float d = min(min(carapace, bellyD), skin);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);

    float3 base = col.rgb;
    float3 L3 = normalize(float3(-0.3, 0.85, 0.45));
    float3 c3;
    if (carapace <= 0.0) {
        float3 n = normalize(float3(sq, sqrt(max(0.03, 1.0 - dot(sq, sq)))));
        float diff = clamp(dot(n, L3), 0.0, 1.0);
        float rimBand = smoothstep(0.78, 0.84, length(sq));
        float2 sm = rimBand > 0.5 ? float2(atan2(sq.y, sq.x) * 6.0, 0.5) : sq / (0.6 + 0.4 * n.z) * 2.2;
        float e = vor_edge(sm + 3.0);
        float seam = 1.0 - smoothstep(0.02, 0.07, e);
        float plate = smoothstep(0.0, 0.35, e);                                  // lighter toward each plate's middle
        float3 alb = base * (0.7 + 0.35 * plate) * (0.85 + 0.3 * vnoise(sq * 6.0 + 2.0));
        alb = mix(alb, base * float3(1.15, 0.95, 0.65), plate * 0.25 * vnoise(sq * 3.0));   // warm patches (tortoiseshell)
        c3 = alb * (0.38 + 0.8 * diff) * (1.0 - seam * 0.5);
        c3 += float3(0.75, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.03, -carapace)) * smoothstep(0.0, 0.8, sq.y) * 0.18;
    } else if (bellyD <= 0.0 && skin > 0.0) {
        c3 = mix(base, float3(0.85, 0.8, 0.55), 0.6) * 0.75;                     // the pale belly
        c3 *= 1.0 - 0.2 * step(0.85, fract(p.x * 7.0));
    } else {
        // skin: greenish, covered in small pale-edged scales, lighter underneath
        float3 sk = float3(0.5, 0.58, 0.42) * (base.g / 0.55);
        float e = vor_edge(p * 16.0);
        sk *= 0.75 + 0.3 * smoothstep(0.02, 0.2, e);
        sk = mix(sk, sk * 0.6 + 0.25, (1.0 - smoothstep(0.02, 0.06, e)) * 0.4);
        c3 = sk * (0.75 + 0.35 * smoothstep(-0.3, 0.2, p.y));
        // the head: a beak line and an eye
        if (headD < 0.0) {
            float beak = abs(p.y - 0.0 + (p.x - 0.86) * 0.25) - 0.006;
            c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.01, beak)) * step(0.8, p.x) * 0.6;
            float re = length(p - float2(0.82, 0.055));
            c3 = mix(c3, c3 * 0.5, 1.0 - smoothstep(0.035, 0.05, re));
            c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.022, 0.03, re));
            c3 = mix(c3, float3(1.0), 1.0 - smoothstep(0.004, 0.009, length(p - float2(0.826, 0.064))));
        }
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.025, -d)) * 0.3;                         // a darker outline
    return float4(c3 * a, a);
}

// whale in the distance: a humpback's silhouette, soft with the distance, darker on top, with long flippers and flukes
float4 draw_whale(float2 c, float phase, float4 col) {
    float2 p = c * float2(2.2, 0.7);
    float flex = sin(phase * 0.6);
    p.y -= flex * 0.06 * smoothstep(0.0, -1.8, p.x);                           // the tail half bends
    float thin = mix(0.28, 1.0, smoothstep(-1.6, 0.4, p.x));
    float body = (length((p - float2(0.15, 0.0)) / float2(1.45, 0.34 * thin)) - 1.0) * 0.3;
    body = smin_k(body, (length((p - float2(1.1, -0.05)) / float2(0.5, 0.26)) - 1.0) * 0.2, 0.08);   // the big head
    // flukes: two lobes at the end of the tail stock
    float2 fp = p - float2(-1.5, 0.0);
    float fl = min(sd_tri(fp, float2(0.12, 0.0), float2(-0.38, 0.22 + flex * 0.05), float2(-0.3, 0.02)),
                   sd_tri(fp, float2(0.12, 0.0), float2(-0.36, -0.2 + flex * 0.05), float2(-0.28, -0.02))) - 0.02;
    // a long pectoral flipper, slowly rowing, and a small dorsal hump
    float fa = -0.5 + sin(phase * 0.4) * 0.12;
    float2 pq = p - float2(0.55, -0.2);
    pq = float2(pq.x * cos(fa) + pq.y * sin(fa), -pq.x * sin(fa) + pq.y * cos(fa));
    float flip = (length((pq - float2(-0.4, 0.0)) / float2(0.45, 0.07)) - 1.0) * 0.07;
    float hump = (length((p - float2(-0.6, 0.17)) / float2(0.14, 0.06)) - 1.0) * 0.06;
    float d = min(min(smin_k(body, hump, 0.05), fl), flip);
    float a = 1.0 - smoothstep(-0.03, 0.05, d);                                    // soft edges: it's far away
    // darker back, a lighter throat with grooves, a faint eye
    float3 c3 = col.rgb * (0.8 + 0.5 * smoothstep(0.2, -0.3, p.y));
    float throat = smoothstep(-0.05, -0.25, p.y) * smoothstep(0.0, 0.8, p.x) * step(body, 0.0);
    c3 = mix(c3, c3 * 1.35, throat * (0.6 + 0.4 * step(0.5, fract(p.y * 30.0))));
    c3 += col.rgb * 0.25 * (1.0 - smoothstep(0.0, 0.04, -d)) * smoothstep(-0.1, 0.3, p.y);
    c3 *= 1.0 - 0.5 * (1.0 - smoothstep(0.02, 0.04, length(p - float2(0.85, -0.08))));
    float aw = a * 0.6;
    return float4(c3 * aw, aw);
}

// corals on the sand (scenery). The sand line is at y = -0.3; `seed` picks the shape and varies it a little.
float4 draw_coral(float2 c, float seed, float t, float4 col) {
    float2 p = c;
    int kind = int(seed) % 3;
    float h = fract(seed) * 6.0;
    float d = 1e3;
    float cover = -1.0;                 // set directly by shapes whose edges aren't a clean distance (the fan's lace)
    float3 c3 = col.rgb;
    if (kind == 0) {
        // branching: a short trunk and forking branches with rounded tips, swaying a little
        d = sd_seg(p, float2(0.0, -0.35), float2(0.0, -0.05)) - 0.075;
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float a = -0.95 + 0.47 * fi + sin(h + fi * 2.1) * 0.12;
            float2 s0 = float2(0.0, -0.08 + 0.05 * fmod(fi, 2.0));
            float len = 0.5 + 0.18 * fract(sin(h * 7.0 + fi * 3.3) * 43.7);
            float2 e = s0 + float2(sin(a), cos(a)) * len;
            e.x += sin(t * 0.7 + fi + h) * 0.03;
            d = min(d, sd_seg(p, s0, e) - 0.055);
            float2 m = mix(s0, e, 0.55);
            float2 e2 = m + float2(sin(a + 0.55), cos(a + 0.55)) * len * 0.42;
            e2.x += sin(t * 0.7 + fi + h + 1.0) * 0.03;
            d = min(d, sd_seg(p, m, e2) - 0.042);
        }
        c3 *= 0.65 + 0.5 * smoothstep(-0.3, 0.8, p.y);                   // lighter toward the tips
        float polyp = step(0.8, vnoise(p * 24.0 + h));
        c3 = mix(c3, c3 * 1.35 + 0.08, polyp * 0.6);
    } else if (kind == 1) {
        // sea fan: a wide lacy fan on a short stem, waving slowly
        // a gorgonian: an irregular mesh of fine twigs (the edges of a stretched voronoi) over a few thicker
        // branches rising from the stem; the outline is ragged, and the twigs thin out toward the rim
        float2 q = p;
        q.x -= sin(t * 0.6 + h) * 0.035 * (p.y + 0.3);
        float2 o = q + float2(0.0, 0.3);
        float rad = length(o);
        float ang = atan2(o.x, o.y);
        float rim = 1.0 + 0.08 * (vnoise(float2(ang * 6.0, h)) - 0.5) + 0.04 * sin(ang * 11.0 + h);
        float fan = (length((q - float2(0.0, 0.28)) / float2(0.85 * rim, 0.62 * rim)) - 1.0) * 0.5;
        fan = max(fan, -0.12 - q.y);
        float outer = smoothstep(0.2, 1.1, rad);
        float2 mp = float2(ang * 6.5, rad * 13.0) + float2(vnoise(q * 4.0 + h), vnoise(q * 4.0 + h + 5.0)) * 0.8;
        float edge = vor_edge(mp);
        float aw = fwidth(edge) + 1e-4;
        float twigW = mix(0.1, 0.05, outer);
        float mesh = 1.0 - smoothstep(twigW - aw, twigW + aw, edge);
        // the main branches: a few wavy ribs fanning out from the stem
        float wa = ang + (vnoise(float2(rad * 4.0, h * 3.0)) - 0.5) * 0.25;
        float rib = abs(fract(wa * 1.6 + 0.5) - 0.5) / 1.6 * rad;
        float ribW = mix(0.03, 0.012, outer);
        float ar = fwidth(rib) + 1e-4;
        float ribs = (1.0 - smoothstep(ribW - ar, ribW + ar, rib)) * (1.0 - smoothstep(0.75, 1.0, rad));
        float afan = fwidth(fan) + 1e-4;
        float inFan = (1.0 - smoothstep(-afan, afan, fan)) * max(mesh, ribs);
        float stem = sd_seg(p, float2(0.0, -0.35), float2(0.0, -0.08)) - 0.05;
        float ast = fwidth(stem) + 1e-4;
        cover = max(inFan, 1.0 - smoothstep(-ast, ast, stem));
        c3 *= 0.6 + 0.5 * smoothstep(-0.3, 0.9, p.y);
        c3 *= 0.85 + 0.3 * vnoise(q * 6.0 + h);                         // patchy color
        c3 = mix(c3, c3 * 1.3 + 0.06, ribs * 0.35);                     // the thick branches catch more light
        c3 = mix(c3, c3 * 1.35 + 0.1, step(0.86, vnoise(q * 30.0 + h)) * 0.6);   // polyps
    } else {
        // brain coral: a dome with winding grooves
        // brain coral: a lumpy dome covered in meandering ridges, the grooves crowding toward its rim
        float2 q = (p - float2(0.0, -0.32)) / float2(0.78, 0.62);
        float lumpy = 0.04 * vnoise(float2(atan2(q.x, q.y) * 3.0, h));
        d = max((length(q) - 1.0 - lumpy) * 0.5, -0.33 - p.y);
        float nz = sqrt(max(0.05, 1.0 - dot(q, q)));
        float2 m = q / pow(nz, 0.6) * 2.2 + h;                              // the dome's surface, stretched near the rim
        // meanders: the grooves are where two warped noises cross their middle, winding lines all over the dome
        float2 wq = m * 4.2 + float2(vnoise(m * 1.5), vnoise(m * 1.5 + 5.0)) * 2.0;
        float g1 = abs(vnoise(wq) - 0.5), g2 = abs(vnoise(wq * 1.9 + 11.0) - 0.5);
        float gv = min(g1 * 1.3, g2 * 1.9);
        float ridge = smoothstep(0.0, 0.16, gv);
        float valley = smoothstep(0.0, 0.35, ridge);
        float3 n = normalize(float3(q, nz));
        float diff = clamp(dot(n, normalize(float3(-0.3, 0.8, 0.5))), 0.0, 1.0);
        c3 *= (0.42 + 0.75 * diff) * (0.4 + 0.6 * valley);
        c3 = mix(c3, c3 * 1.25 + 0.04, smoothstep(0.75, 1.0, ridge) * 0.5);  // the ridge tops
        c3 *= 0.9 + 0.2 * vnoise(q * 8.0 + h);
    }
    float aa = fwidth(d) + 1e-4;
    float inside = cover >= 0.0 ? cover : 1.0 - smoothstep(-aa, aa, d);
    // the sand line hides the base
    inside *= smoothstep(-0.36, -0.3, p.y);
    return float4(c3 * inside, inside) * col.a;
}

// `open` (0…1): the lid rises and tips back, showing a heap of gold coins inside
float4 draw_chest(float2 c, float phase, float glow, float4 col, float open) {
    float2 p = c;
    float body = sd_box(p - float2(0.0, -0.33), float2(0.78, 0.37), 0.04);
    float2 q = p - float2(0.0, 0.11 + open * 0.34);
    q.y /= 1.0 - open * 0.5;                                                // tipping back: seen from the front, it gets shorter
    float lid = max((length(q / float2(0.82, 0.42)) - 1.0) * 0.35, -q.y);   // rounded lid, a bit open
    float d = min(body, lid);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);
    // wood: planks with grain, each its own shade; the lid's planks bend over its curve
    bool onLid = lid < body;
    float pv = onLid ? asin(clamp(q.y / 0.42, 0.0, 1.0)) / 1.5708 * 4.0 + 10.0 : (p.y + 1.0) * 5.5;   // the lid's planks run along it, crowding toward the top
    float plank = floor(pv);
    float seam = 1.0 - smoothstep(0.0, 0.07, min(fract(pv), 1.0 - fract(pv)));
    float grain = vnoise(float2(p.x * 3.0 + plank * 5.0, fract(pv) * 6.0 + plank * 3.0));
    float3 wood = col.rgb * (0.82 + 0.25 * hash21(float2(plank, onLid ? 1.0 : 0.0))) * (0.85 + 0.25 * grain);
    wood *= 1.0 - seam * 0.45;
    // light from above: the lid's curve is lit on top, the body darker toward the sand
    float lidN = clamp(q.y / 0.42, 0.0, 1.0);
    wood *= onLid ? (0.7 + 0.45 * lidN) : (0.62 + 0.38 * smoothstep(-0.7, 0.05, p.y));
    wood = mix(wood, wood * float3(0.75, 0.9, 0.7), smoothstep(0.62, 0.85, vnoise(p * 4.0 + 2.0)) * 0.4);   // old algae stains
    // iron: two straps over body and lid, a band along the body, corner caps; shaded, with rivets
    float3 metal = float3(0.5, 0.45, 0.36) * dot(col.rgb, float3(0.9));
    float strapX = abs(abs(p.x) - 0.5);
    float band = max(step(strapX, 0.06), step(abs(p.y + 0.3), 0.045) * step(p.y, 0.04));
    band = max(band, step(0.68, abs(p.x)) * step(p.y, 0.04) * step(abs(p.y + 0.33), 0.33) * step(abs(p.y + 0.33), 0.33));
    float mshade = 0.75 + 0.4 * (1.0 - strapX / 0.06) * step(strapX, 0.06) + 0.25 * smoothstep(-0.7, 0.4, p.y);
    float2 rv = float2(strapX, fract((p.y + 1.0) * 6.0) - 0.5);
    float rivet = (1.0 - smoothstep(0.018, 0.028, length(float2(rv.x, rv.y / 6.0)))) * step(p.y, 0.02);
    float3 c3 = mix(wood, metal * mshade + rivet * 0.25, band);
    c3 *= 1.0 - band * (1.0 - smoothstep(0.0, 0.015, 0.06 - strapX)) * step(strapX, 0.06) * 0.3;   // the strap's edges
    // the lock: a brass plate with a keyhole
    float plate = sd_box(p - float2(0.0, -0.02), float2(0.085, 0.1), 0.025);
    float key = min(length(p - float2(0.0, 0.0)) - 0.022, sd_box(p - float2(0.0, -0.04), float2(0.01, 0.03), 0.0));
    float3 brass = float3(0.85, 0.66, 0.3) * dot(col.rgb, float3(0.8)) * 1.3 * (0.8 + 0.4 * smoothstep(-0.12, 0.08, p.y));
    c3 = mix(c3, brass, 1.0 - step(0.0, plate));
    c3 = mix(c3, float3(0.04), (1.0 - step(0.0, key)) * (1.0 - step(0.0, plate)));
    // dark along the outline, so the box reads as a solid
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.04, -d)) * 0.35;
    // treasure glow through the gap under the lid
    float pulse = (0.55 + 0.45 * sin(phase * 1.3)) * glow;
    float gap = (1.0 - smoothstep(0.0, 0.035, abs(p.y - 0.075))) * step(abs(p.x), 0.74);
    float halo = exp(-max(p.y - 0.08, 0.0) * 6.0) * step(0.075, p.y) * (1.0 - smoothstep(0.5, 0.9, abs(p.x))) * 0.35;
    float3 gold = float3(1.0, 0.8, 0.35);
    float a = max(inside, (gap + halo) * pulse);
    float3 outc = c3 * inside + gold * (gap * 1.2 + halo) * pulse;
    if (open > 0.01) {
        // the inside: the dark back wall between the rim and the raised lid
        float back = step(abs(p.x), 0.76) * step(0.0, p.y) * step(p.y, 0.1 + open * 0.34) * (1.0 - inside);
        outc = mix(outc, col.rgb * 0.3 * (0.8 + 0.2 * step(fract(p.x * 6.0), 0.9)), back);
        a = max(a, back);
        // the treasure: a heap of coins over the rim, glittering, and the light pouring out of it
        float heapTop = 0.04 + open * 0.27 * (1.0 - pow(p.x / 0.74, 2.0));
        float heap = step(abs(p.x), 0.74) * step(p.y, heapTop) * step(-0.02, p.y) * step(body, 0.02);
        float2 cg = p * float2(14.0, 18.0);
        float coin = 1.0 - smoothstep(0.25, 0.42, length(fract(cg + float2(floor(cg.y) * 0.5, 0.0)) - 0.5));
        float twinkle = pow(max(0.0, sin(phase * 3.0 + floor(cg.x) * 1.7 + floor(cg.y) * 2.3)), 8.0);
        float3 goldC = mix(float3(0.85, 0.6, 0.18), float3(1.0, 0.88, 0.45), coin) + float3(1.0) * twinkle * 0.6;
        outc = mix(outc, goldC, heap * (1.0 - step(lid, 0.0)));
        float shine = exp(-max(p.y - heapTop, 0.0) * 5.0) * step(heapTop, p.y) * step(abs(p.x), 0.8) * (1.0 - step(lid, 0.0)) * open * 0.55;
        outc += float3(1.0, 0.8, 0.4) * shine;
        a = max(a, max(heap, shine));
    }
    return float4(outc, min(a, 1.0));
}

// ---------- the music fish (a betta with a flowing, iridescent tail) and the notes it lets out ----------

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
float4 draw_shark(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(1.6, 0.7);
    float sway = sin(phase * 2.2);
    p.y -= sway * 0.06 * smoothstep(0.2, -1.3, p.x);                       // the back half follows the tail
    // a torpedo: pointed snout, deepest behind the gills, a slim tail stock
    float thin = mix(0.3, 1.0, smoothstep(-1.1, 0.1, p.x)) * mix(1.0, 0.72, smoothstep(0.55, 1.25, p.x));
    float body = (length((p - float2(0.08, 0.0)) / float2(1.22, 0.31 * thin)) - 1.0) * 0.28;
    // the tail: a long upper lobe and a shorter lower one
    float2 tp = p - float2(0.0, sway * 0.08);
    float tail = min(sd_tri(tp, float2(-0.95, 0.03), float2(-1.55, 0.52), float2(-1.2, -0.02)),
                     sd_tri(tp, float2(-0.98, -0.02), float2(-1.42, -0.3), float2(-1.18, 0.02))) - 0.015;
    // fins: a tall swept-back dorsal with a hollow trailing edge, a second small one, a long pectoral, the pelvic
    float dorsal = max(sd_tri(p, float2(-0.18, 0.22), float2(0.3, 0.26), float2(-0.28, 0.66)),
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
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.01, mouth)) * step(0.86, p.x) * step(p.x, 1.1) * 0.35;
    float re = length(p - float2(1.0, 0.055));
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.03, 0.042, re));
    c3 = mix(c3, float3(0.9), 1.0 - smoothstep(0.004, 0.01, length(p - float2(1.008, 0.065))));
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
float4 draw_bottle(float2 c, float phase, float glow, float4 col) {
    float2 p = c * float2(0.9, 0.5);
    float a = 0.16;
    p = float2(p.x * cos(a) + p.y * sin(a), -p.x * sin(a) + p.y * cos(a));
    float body = sd_seg(p, float2(-0.5, 0.0), float2(0.18, 0.0)) - 0.2;
    float neck = sd_seg(p, float2(0.18, 0.0), float2(0.62, 0.0)) - 0.075;
    float glass = min(body, neck);
    float cork = sd_box(p - float2(0.7, 0.0), float2(0.08, 0.07), 0.02);
    float paper = sd_box(p - float2(-0.16, -0.01), float2(0.26, 0.085), 0.04);
    float d = min(glass, cork);
    float aa = fwidth(d) + 1e-4;
    float inG = 1.0 - smoothstep(-aa, aa, glass);
    float rim = smoothstep(-0.05, 0.0, glass) * inG;
    float shine = (1.0 - smoothstep(0.0, 0.03, abs(p.y - 0.11))) * step(p.x, 0.1) * step(-0.45, p.x) * inG;
    float inP = (1.0 - smoothstep(-aa, aa, paper)) * inG;
    float3 c3 = col.rgb * (0.85 + 0.5 * rim) * inG;
    float alphaG = inG * (0.55 + 0.4 * rim);
    float3 paperC = float3(0.95, 0.9, 0.75) * (1.0 + glow * (0.8 + 0.4 * sin(phase * 4.0)));
    c3 = mix(c3, paperC, inP * 0.9);
    alphaG = max(alphaG, inP * 0.95);
    c3 += float3(1.0) * shine * 0.6;
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
    float d = min(wood, hubD);
    float aa = fwidth(d) + 1e-4;
    float inW = 1.0 - smoothstep(-aa, aa, wood);
    float inH = 1.0 - smoothstep(-aa, aa, hubD);
    float grain = 0.85 + 0.15 * sin(q.x * 40.0 + vnoise(q * 6.0) * 4.0);
    float3 woodC = col.rgb * grain * (0.75 + 0.35 * smoothstep(-0.8, 0.8, c.y));
    float3 hubC = hub * (0.8 + 0.4 * (1.0 - r / 0.15)) + float3(0.25) * (1.0 - smoothstep(0.0, 0.07, length(p - float2(-0.04, 0.05))));
    float3 c3 = woodC * inW + hubC * inH;
    float inside = max(inW, inH);
    float halo = exp(-max(d, 0.0) * 24.0) * glow * 0.45 * (1.0 - inside) * edge_fade(c);
    float hubGlow = exp(-max(hubD, 0.0) * 12.0) * 0.35 * (1.0 - inside) * edge_fade(c);
    return float4((c3 * inside + col.rgb * halo + hub * hubGlow) * col.a, (inside + halo * 0.5 + hubGlow * 0.4) * col.a);
}

float4 draw_presence(int kind, float2 c, float phase, float glow, float4 col, float4 extra) {
    switch (kind) {
        case 25: return draw_shark(c, phase, glow, col);
        case 26: return draw_submarine(c, phase, glow, col);
        case 27: return draw_bottle(c, phase, glow, col);
        case 28: return draw_hourglass(c, phase, glow, col, extra.y);
        case 29: return draw_anchor(c, phase, glow, col);
        case 31: return draw_helm(c, phase, glow, col, extra.yzw);
        default: return draw_flag(c, phase, glow, col);
    }
}

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
        outc = draw_chest(c, in.phase, in.glow, in.color, in.extra.y);
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
    o.glow = float4(outc.rgb * emissive(k, in.glow), outc.a);       // opaque things also cover the glow behind them
    return o;
}

// ---------- bloom (Renderer): what glows, reduced, blurred and added back ----------

struct PostOut { float4 position [[position]]; float2 uv; };

vertex PostOut post_vertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    PostOut o;
    o.position = float4(p[vid], 0, 1);
    o.uv = float2((p[vid].x + 1.0) * 0.5, 1.0 - (p[vid].y + 1.0) * 0.5);
    return o;
}

// to a quarter of the size: 4 bilinear taps (16 texels)
fragment float4 bloom_down(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]], sampler s [[sampler(0)]]) {
    float2 px = 1.0 / float2(src.get_width(), src.get_height());
    float4 c = src.sample(s, in.uv + px * float2(-1, -1)) + src.sample(s, in.uv + px * float2(1, -1))
             + src.sample(s, in.uv + px * float2(-1, 1)) + src.sample(s, in.uv + px * float2(1, 1));
    return float4(c.rgb * 0.25, 1.0);
}

// 9-tap gaussian in 5 bilinear samples, along `dir` (in texels)
fragment float4 bloom_blur(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]], sampler s [[sampler(0)]],
                           constant float2& dir [[buffer(0)]]) {
    float2 px = dir / float2(src.get_width(), src.get_height());
    float3 c = src.sample(s, in.uv).rgb * 0.2270270270;
    c += (src.sample(s, in.uv + px * 1.3846153846).rgb + src.sample(s, in.uv - px * 1.3846153846).rgb) * 0.3162162162;
    c += (src.sample(s, in.uv + px * 3.2307692308).rgb + src.sample(s, in.uv - px * 3.2307692308).rgb) * 0.0702702703;
    return float4(c, 1.0);
}

// The last pass, added on top of the image (one + one): the bloom, and the front glass you look through:
// a diagonal sheen, specks of dust, and mist with drops in the top corners.
fragment float4 bloom_add(PostOut in [[stage_in]], texture2d<float> bloom [[texture(0)]], sampler s [[sampler(0)]],
                          constant float& strength [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
    float3 c = strength > 0.001 ? bloom.sample(s, in.uv).rgb * strength : float3(0.0);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float2 world = uv * u.res;
    float aspect = u.res.x / u.res.y;
    float sheen = exp(-pow((uv.x * 0.7 + uv.y - 1.05) / 0.07, 2.0)) * 0.035 + exp(-pow((uv.x * 0.7 + uv.y - 1.2) / 0.025, 2.0)) * 0.022;
    float2 cell = floor(world / 7.0);
    float speck = step(0.9982, hash21(cell)) * (1.0 - smoothstep(0.08, 0.2, length(fract(world / 7.0) - 0.5))) * 0.16;
    float glass = sheen + speck;
    float corner = max(1.0 - smoothstep(0.0, 0.22, length(float2(uv.x * aspect, uv.y) - float2(0.0, 1.0))),
                       1.0 - smoothstep(0.0, 0.22, length(float2((1.0 - uv.x) * aspect, uv.y) - float2(0.0, 1.0))));
    if (corner > 0.0) {
        float mist = corner * (0.45 + 0.55 * vnoise(world * 0.03)) * 0.1;
        float drop = corner * step(0.93, hash21(floor(world / 11.0) + 7.0)) * (1.0 - smoothstep(0.18, 0.3, length(fract(world / 11.0) - 0.5))) * 0.2;
        glass += mist + drop;
    }
    c += float3(0.85, 0.92, 0.96) * glass * (0.55 + 0.45 * u.light);
    return float4(c, 0.0);
}
"""#
