// Constellations: the resident assistant (the moray, dressed) as a space station adrift among the stars. A ring that
// turns slowly on a central hub, two spokes, a long truss with solar panels out to both sides, a docking module, and
// navigation lights blinking. It doesn't face a way (the app doesn't turn a sitting presence), and the app makes it
// bigger as it comes out to talk. Its state shows in its windows and its beacon: extra.w 0 idle (windows dark, a slow
// dim beacon), 1 busy (windows lit, the ring turning faster), 2 waiting (glowing, beacon in its color), 5 error (a red
// beacon), 6 done (a green blink). p = c * (1.2, 1.0).
float4 draw_constellations_station(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.2, 1.0);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    int state = int(extra.w + 0.5);
    float busy = state == 1 ? 1.0 : 0.0;
    float lumK = max(col.r, max(col.g, col.b));
    // the ring, seen a little from the side (an ellipse), turning: its segments pass around it
    float2 rq = p / float2(1.0, 0.42);
    float rr = length(rq);
    float ringD = abs(rr - 0.62) * 0.42 - 0.035;
    float ang = atan2(rq.y, rq.x);
    float spin = phase * (0.12 + 0.2 * busy);
    float segs = fract((ang + spin) / 6.28318 * 12.0);
    float back = step(0.0, p.y);                                               // the half behind the hub is darker
    // the truss and the panels across it, the hub and a docking module on top
    float truss = sd_box(p, float2(1.02, 0.018), 0.0);
    float pan = min(sd_box(p - float2(-0.9, 0.0), float2(0.13, 0.3), 0.01), sd_box(p - float2(0.9, 0.0), float2(0.13, 0.3), 0.01));
    float hub = (length(p / float2(0.16, 0.2)) - 1.0) * 0.16;
    float dock = sd_box(p - float2(0.0, 0.28), float2(0.05, 0.1), 0.02);
    float spokes = min(sd_seg(p, float2(-0.6, 0.0), float2(0.6, 0.0)), sd_seg(p, float2(0.0, -0.26), float2(0.0, 0.26))) - 0.012;
    float solid = min(min(hub, dock), min(truss, spokes));
    float d = min(min(ringD, pan), solid);
    float aa = px;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 metal = mix(float3(0.78, 0.8, 0.85), col.rgb, 0.25) * lumK;
    float3 c3 = metal;
    if (ringD < min(pan, solid)) {
        c3 = metal * (0.78 + 0.12 * smoothstep(0.1, 0.0, abs(segs - 0.5) - 0.4)) * (1.0 - back * 0.35);
        c3 *= 0.85 + 0.25 * smoothstep(0.62, 0.66, rr);                       // the outer edge catches the light
        // windows along the ring: a row of small lights, lit in the state's way
        float2 wq = float2((segs - 0.5) * 0.32, (rr - 0.62) * 0.42);
        float win = exp(-dot(wq, wq) / max(0.0003, px * px * 0.8)) * (1.0 - back * 0.5);
        float lit = state == 0 ? 0.06 : 0.7 + 0.5 * busy;
        c3 += mix(float3(1.0, 0.85, 0.55), col.rgb, 0.3) * win * lit;
    } else if (pan < solid) {
        float2 g = fract((p - float2(0.0, 0.3)) * float2(10.0, 12.0));
        c3 = mix(float3(0.12, 0.2, 0.42), float3(0.25, 0.38, 0.7), 0.4) * (0.8 + 0.4 * step(0.1, min(g.x, g.y)));
        c3 += float3(0.5, 0.6, 0.9) * pow(max(0.0, sin(phase * 0.07 + p.y * 2.0)), 30.0) * 0.6;   // the sun sliding over them
    } else {
        float3 n = normalize(float3(p / float2(0.16, 0.2), 0.8));
        c3 = metal * (0.55 + 0.5 * max(0.0, dot(n, normalize(float3(-0.4, 0.7, 0.6)))));
    }
    // the beacon on the dock and the lights at the panels' tips
    float3 beaconC = state == 5 ? float3(1.0, 0.3, 0.25) : state == 6 ? float3(0.45, 1.0, 0.55)
                   : state == 2 ? mix(col.rgb, float3(1.0), 0.3) : float3(1.0, 0.95, 0.85);
    float rate = state == 0 ? 0.25 : state == 5 ? 1.2 : 0.6;
    float blink = smoothstep(0.75, 1.0, sin(phase * rate) * 0.5 + 0.5) * (state == 0 ? 0.5 : 1.0);
    float bl = exp(-dot(p - float2(0.0, 0.4), p - float2(0.0, 0.4)) / max(0.0016, px * px * 2.0)) * blink;
    float tips = exp(-dot(float2(abs(p.x) - 1.05, p.y), float2(abs(p.x) - 1.05, p.y)) / max(0.0012, px * px * 2.0))
               * (0.5 + 0.5 * sin(phase * 0.9 + sign(p.x) * 1.6));
    float3 tipC = p.x > 0.0 ? float3(0.4, 1.0, 0.5) : float3(1.0, 0.35, 0.3);
    float3 rgb = c3 * a;
    rgb += col.rgb * glow * 0.45 * a;
    rgb += beaconC * bl * 1.5 + tipC * tips * 0.9;
    float al = clamp(a + bl + tips * 0.8, 0.0, 1.0);
    // attention: a soft halo in its color around it
    float halo = glow * exp(-max(d, 0.0) * 6.0) * (1.0 - smoothstep(0.65, 1.0, max(abs(c.x), abs(c.y))));
    rgb += col.rgb * halo * (1.0 - al);
    al += halo * (1.0 - al) * 0.55;
    return float4(rgb, al) * col.a;
}
