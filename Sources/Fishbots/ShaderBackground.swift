/// The background pass: water, light rays, the surface, the sand, the distant scenery and the seaweed.
let shaderBackground = #"""
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

// The surface's height around its rest line at x (0…1 across the tank): the water line, and the lens that throws
// the caustics on the sand (wave_focus).
float surface_wave(float x, float t, float waves) {
    return (0.006 * sin(x * 30.0 + t * 1.5) + 0.004 * sin(x * 71.0 - t * 2.3)) * (1.0 + 2.5 * waves)
         + 0.007 * waves * sin(x * 13.0 - t * 3.1) - 0.004 * waves;
}

// How much the surface above x gathers the light below it (1: as much as flat water). Each crest is a lens: the
// brightness goes with the surface's curvature, 1 / (1 - gain × curvature), so the bands on the sand travel with
// the waves and sharpen into lines as the water gets rough.
float wave_focus(float x, float t, float waves) {
    float curv = (0.45 * sin(x * 30.0 + t * 1.5) + 0.55 * sin(x * 71.0 - t * 2.3) + 0.4 * waves * sin(x * 13.0 - t * 3.1))
               / (1.0 + 0.4 * waves);
    float gain = mix(0.62, 0.93, waves);
    return min(sqrt(1.0 - gain * gain) / max(1.0 - gain * curv, 0.06), 4.0);
}

// a pack theme's background (generated at "@fish-kinds", see FishKinds.shaderSource)
float4 draw_background_pack(int k, float2 uv, float t, float light, float2 gaze, float3 water, float4 extra);

// weeds[k]: x (0…1), height (0…1), bend (how far the tip is pushed, in widths), kind (0 blade, 1 kelp, 2 leafy).
// From Tank.weedUniforms.
fragment Frag2 bg_fragment(BgOut in [[stage_in]], constant Uniforms& u [[buffer(0)]], constant Theme& th [[buffer(1)]],
                            constant float4* weeds [[buffer(2)]]) {
    float2 uv = float2(in.position.x / u.pix.x, 1.0 - in.position.y / u.pix.y);
    float aspect = u.res.x / u.res.y;
    float t = u.time;
    float L = u.light;
    float3 lampL = lamp_light(uv * u.res, u);                          // a lanternfish's lure nearby

    float3 deep = th.deep.rgb;
    float3 shallow = th.shallow.rgb;
    float3 col = mix(deep, shallow, pow(uv.y, 1.3)) * (0.5 + 0.5 * L);
    // daylight scattered in the upper water: brighter toward the surface and toward the sun's side, by day only
    float day = L * (1.0 - u.grade.w);
    col += shallow * (0.22 * pow(uv.y, 2.2) + 0.12 * exp(-pow((uv.x - u.sky.x) * 2.2, 2.0)) * uv.y * uv.y) * day * u.sky.y * 2.6;

    float2 q = float2(uv.x * aspect, uv.y);
    // refraction: near the surface the light wobbles, as if through little waves (more with the waves gauge)
    q += float2(sin(uv.y * 70.0 + t * 2.1 + uv.x * 9.0), cos(uv.x * 55.0 * aspect - t * 1.7))
         * 0.0035 * (1.0 + 2.0 * u.scene.x) * smoothstep(0.7, 0.96, uv.y);

    // light rays coming from the surface
    float r1 = sin((q.x + q.y * 0.35) * 9.0 + t * 0.25) * 0.5 + 0.5;
    float r2 = sin((q.x - q.y * 0.20) * 15.0 - t * 0.17) * 0.5 + 0.5;
    float rays = pow(r1 * r2, 3.0) * smoothstep(0.1, 1.0, uv.y);
    // some beams strong, some missing, drifting slowly: clouds and waves above never let it through evenly
    rays *= 0.35 + 1.3 * smoothstep(0.3, 0.75, vnoise(float2((q.x + q.y * 0.3) * 2.3 + t * 0.03, 7.7)));
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
    float surf = 0.965 + surface_wave(uv.x, t, waves);
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
    if (th.pack.y < 0.5 && uv.y < 0.45) {                                // (the reef never goes higher: skip the noise above it)
        float rx = uv.x + u.gaze.x * 0.003;
        float ridge = 0.12 + 0.1 * vnoise(float2(rx * 4.0, 2.7)) + 0.05 * vnoise(float2(rx * 13.0, 5.3));
        ridge += 0.09 * smoothstep(0.17, 0.0, abs(rx - 0.24)) + 0.07 * smoothstep(0.2, 0.0, abs(rx - 0.8));
        // further still: a taller, paler range almost lost in the haze
        float fx = uv.x + u.gaze.x * 0.0015;
        float far = 0.2 + 0.12 * vnoise(float2(fx * 2.6, 9.1)) + 0.04 * vnoise(float2(fx * 9.0, 3.3))
                  + 0.07 * smoothstep(0.22, 0.0, abs(fx - 0.55));
        if (uv.y < far) {
            col = mix(col, fog * 0.8, 0.34 * (0.6 + 0.4 * smoothstep(far - 0.14, far, uv.y)));
            col += fog * 0.1 * (1.0 - smoothstep(0.0, 0.01, far - uv.y)) * L;
        }
        if (uv.y < ridge) {
            col = mix(col, fog * 0.5, 0.66 * (0.75 + 0.25 * smoothstep(ridge - 0.1, ridge, uv.y)));
            col += fog * 0.22 * (1.0 - smoothstep(0.0, 0.006, ridge - uv.y)) * L;     // its top catches a little light
        }
    }
    // a pack's own background, over the water and behind the seaweed
    if (th.pack.x > 0.5) {
        float sandLine = 0.075 + 0.018 * sin(uv.x * 7.0 + 1.3) + 0.008 * sin(uv.x * 23.0);
        float4 b = draw_background_pack(int(th.pack.x - 0.5), uv, t, L, u.gaze, col, float4(aspect, u.grade.w, sandLine, 0.0));
        col = col * (1.0 - b.a) + b.rgb;
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
            col = mix(col, mix(fog, th.farWeed.rgb, 0.35) + th.weedHigh.rgb * lampL * 0.35, blade * 0.5);
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
            } else if (kind == 3) {
                // a reed: a straight, stiff stem that barely sways, a few with a cattail's brown head near the top
                float dxr = (uv.x + u.gaze.x * 0.012 - x0 - sway * 0.25) * aspect;
                float w = 0.0032 * (1.0 - 0.5 * k01);
                blade = 1.0 - smoothstep(w * 0.5, w, abs(dxr));
                green = mix(green, float3(0.45, 0.5, 0.25) * (0.45 + 0.55 * L), 0.35);
                green *= 0.85 + 0.25 * smoothstep(-w, w, dxr);
                if (fmod(fk, 2.0) < 0.5) {
                    float hy = (k01 - 0.86) / 0.07;
                    float head = (1.0 - smoothstep(0.8, 1.0, length(float2(dxr / 0.0075, hy)))) * step(abs(hy), 1.0);
                    blade = max(blade, head);
                    green = mix(green, float3(0.38, 0.24, 0.13) * (0.45 + 0.6 * L) * (0.85 + 0.3 * smoothstep(-0.007, 0.007, dxr)), head);
                }
            } else if (kind == 4) {
                // a ribbon: thin, dark and long, waving a lot, a little see-through
                float dxw = dx - sin(yy * 30.0 - t * 1.6 + fk) * 0.004 * k01 * aspect;
                float w = 0.006 * (1.0 - 0.6 * k01);
                blade = (1.0 - smoothstep(w * 0.4, w, abs(dxw))) * 0.8;
                green = mix(green, float3(0.12, 0.18, 0.16) * (0.45 + 0.55 * L), 0.5);
                green *= 0.8 + 0.3 * smoothstep(-w, w, dxw);
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
            // a lamp nearby (a lanternfish's lure) lights it in its own color, the edges facing it a little more
            green += (mix(th.weedLow.rgb, th.weedHigh.rgb, k01) * 1.5 + 0.04) * lampL;
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
        float3 sand = mix(th.sandDark.rgb, th.sandLight.rgb, smoothstep(0.2, 0.85, g)) * (0.5 + 0.62 * L);
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
        // gathered by the real waves: under each crest of the surface a band of light, following the slant of the rays
        // down from where it crossed the water line, and bending a little as the floor goes back
        // (two sheets of it, leaning opposite ways into the distance, so the bands cross into a net)
        float xs = uv.x - 0.35 * (0.965 - uv.y) / aspect + (vnoise(fq * float2(1.5, 5.0)) - 0.5) * 0.03;
        float lean = (1.0 / persp - 1.0) * 0.011;
        float wf = 0.5 * (wave_focus(xs + lean, t, waves) + wave_focus(xs - lean * 1.7 + 0.37, t * 0.93, waves));
        float net = mix(c, cs, 0.7);
        float sunny = (0.12 + 0.22 * u.sky.y * (1.0 - u.grade.w)) * L;                 // stronger under a high sun
        sand += float3(0.6, 0.7, 0.6) * net * (0.35 + 0.75 * wf) * sunny;
        sand *= 1.0 + (wf - 1.0) * 2.8 * sunny * (0.8 + 0.5 * net);                     // the bands: brighter under a crest, dimmer between
        // rain: each drop's ring of light spreading on the sand under it (flattened by the slant), more with more rain
        if (u.scene.y > 0.01) {
            float rings = 0.0;
            for (int i = 0; i < 2; i++) {
                float fi = float(i);
                float2 rc = float2(fp.x, fp.y * 0.36) * (5.0 + fi * 2.0) + fi * 13.7;
                float2 id = floor(rc);
                float h = hash21(id + fi * 31.0);
                float tt = t / (1.3 + h * 1.5) + h * 9.0;
                float n = floor(tt), ph = fract(tt);
                if (hash21(id + n * 0.371 + 5.0) > u.scene.y * 0.85) continue;
                float2 ctr = (float2(hash21(id + n * 1.3 + 1.0), hash21(id + n * 0.7 + 4.0)) - 0.5) * 0.3;
                float rr = length(fract(rc) - 0.5 - ctr);
                float w = 0.02 + ph * 0.02;
                rings += (exp(-pow((rr - ph * 0.33) / w, 2.0)) + exp(-pow((rr - ph * 0.19) / w, 2.0)) * 0.4) * (1.0 - ph) * (1.0 - ph);
            }
            sand += float3(0.62, 0.74, 0.76) * rings * 0.6 * L * (1.0 - 0.6 * depth);
        }
        sand += th.sandLight.rgb * lampL * 0.45;                           // a lamp's pool of light on the floor
        // darker toward the glass, hazier toward the back, and the back line catches a little light
        sand *= mix(0.78, 1.0, smoothstep(0.0, 0.7, depth));
        // a pool of light where the sun stands over it
        sand *= 1.0 + 0.35 * exp(-pow((uv.x - u.sky.x) * 2.6, 2.0)) * u.sky.y * 2.6 * L * (1.0 - u.grade.w);
        sand = mix(sand, fog * 0.9, depth * depth * 0.35);
        sand += th.sandLight.rgb * (1.0 - smoothstep(0.0, 0.006, sandH - uv.y)) * 0.12 * L;
        float edge = smoothstep(sandH - 0.004, sandH, uv.y);
        col = mix(sand, col, edge);
    }

    // murky water
    col = mix(col, th.murk.rgb * (0.45 + 0.55 * L), u.turbidity * 0.7);

    // glass: vignette, reflection and alert at the edges
    float2 d = (uv - 0.5) * float2(1.1, uv.y < 0.5 ? 0.95 : 1.3);
    float vig = clamp(1.0 - dot(d, d) * 1.1, 0.0, 1.0);
    col *= 0.42 + 0.58 * vig;
    col += (1.0 - smoothstep(0.0, 0.03, abs((uv.x * 0.6 + uv.y) - 1.25))) * 0.035;
    col += float3(0.6, 0.06, 0.05) * u.alert * (1.0 - vig) * 0.9;
    // lightning: a cold flash, stronger near the surface
    col += u.flashColor.rgb * u.flash * (0.45 + 0.55 * uv.y);

    col = scene_tint(col, 1.0, u);
    Frag2 o;
    o.color = float4(col * u.grade.rgb, 1.0);
    o.glow = float4(glowBg * u.grade.rgb * (1.0 - u.turbidity * 0.7), 1.0);
    return o;
}

// ---------- sprites (fish, bubbles, rings…) ----------

"""#
