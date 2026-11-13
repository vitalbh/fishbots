// Constellations: what crosses the sky now and then, a comet far away and a satellite.

// A comet, far away and slow: a bright head in a round coma, a straight blue ion tail and a wider, curved, paler dust
// tail streaming behind it. Faces +x. p = c * (3.0, 0.7).
float4 draw_constellations_comet(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(3.0, 0.7);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    float2 head = float2(2.35, 0.0);
    float2 q = p - head;
    float r = length(q);
    float core = 1.0 - smoothstep(max(0.03, px) * 0.4, max(0.03, px), r);
    float coma = exp(-r * r / 0.02) * 0.8 + exp(-r * r / 0.12) * 0.25;
    // the tails: behind the head (q.x < 0), widening and fading
    float back = max(-q.x, 0.0);
    float u = clamp(back / 5.0, 0.0, 1.0);
    float ion = exp(-abs(q.y) / max(0.012 + 0.02 * u, px * 0.6)) * (1.0 - u) * step(q.x, 0.05)
              * (0.8 + 0.2 * sin(back * 6.0 - phase * 0.8));
    float dy = q.y + back * back * 0.025;                                         // the dust tail bends away
    float dustT = exp(-pow(dy / (0.04 + 0.13 * u), 2.0)) * (1.0 - u) * smoothstep(0.0, 0.3, back) * 0.6;
    float3 rgb = float3(1.0, 0.98, 0.92) * (core + coma) + float3(0.45, 0.7, 1.0) * ion * 0.5
               + mix(float3(1.0, 0.92, 0.75), col.rgb, 0.3) * dustT * 0.45;
    float a = clamp(core + coma * 0.8 + ion * 0.45 + dustT * 0.4, 0.0, 1.0);
    float fade = 1.0 - smoothstep(0.75, 1.0, max(abs(c.x), abs(c.y)));
    return float4(rgb, a) * fade * col.a;
}

// A satellite: small, a body with two panels, catching the sun as it turns (a slow flare), with a blinking light.
// Small in the tank it's a steady moving point that brightens now and then. Faces +x. p = c * (2.0, 1.0).
float4 draw_constellations_satellite(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(2.0, 1.0);
    float px = max(fwidth(p.x), fwidth(p.y)) + 1e-5;
    float body = sd_box(p, float2(0.18, 0.14), 0.03);
    float panels = min(sd_box(p - float2(-0.8, 0.0), float2(0.5, 0.2), 0.0), sd_box(p - float2(0.8, 0.0), float2(0.5, 0.2), 0.0));
    float strut = sd_box(p, float2(0.4, 0.025), 0.0);
    float d = min(min(body, panels), strut);
    float a = 1.0 - smoothstep(-px, px, d);
    float3 rgb = float3(0.75, 0.74, 0.7);
    if (panels < min(body, strut)) {
        float2 g = fract(float2(p.x * 5.0, p.y * 5.0));
        rgb = mix(float3(0.16, 0.24, 0.42), float3(0.3, 0.42, 0.7), smoothstep(0.1, 0.0, min(g.x, g.y)) * 0.0 + 0.4);
        rgb *= 0.8 + 0.4 * step(0.08, min(g.x, g.y));
    }
    // the flare: once in a while the panels catch the sun
    float flare = pow(max(0.0, sin(phase * 0.13 + extra.y * 6.0)), 40.0);
    rgb += float3(1.0, 0.95, 0.85) * flare * 0.9;
    // seen small it's mostly its light: a soft point
    float r = length(p);
    float pt = exp(-r * r / 0.25) * (0.6 + 1.2 * flare);
    float blink = step(0.85, fract(phase * 0.12 + extra.y)) * exp(-length(p - float2(0.0, 0.2)) * 8.0);
    float3 o = rgb * a * 0.7 + float3(0.9, 0.92, 1.0) * pt * (1.0 - a * 0.5) + float3(1.0, 0.3, 0.25) * blink;
    float al = clamp(a * 0.85 + pt * 0.8 + blink, 0.0, 1.0);
    float fade = 1.0 - smoothstep(0.8, 1.0, max(abs(c.x), abs(c.y)));
    return float4(o, al) * fade * col.a;
}
