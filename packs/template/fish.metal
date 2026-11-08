// A fish: float4 draw_<name>(float2 c, float phase, float glow, float4 col, float4 extra)
//   c      -1…1 over the quad (1.25 × 0.8 of the fish's size), y up, the fish facing +x (the app mirrors it)
//   phase  runs as it swims: use it for the wave along the body and the tail
//   glow   0…1 when it lights up (a note, waiting for you): add a little of its color
//   col    the project's color (rgb) and its opacity (a)
//   extra  y: the project's pattern (0…7) + cut × 8, w: how full it is (0…1) + 2 while it sleeps
// Return premultiplied color: float4(rgb * a, a).
// A deep-bodied fish with a forked tail, see-through fins, lit from above; four patterns by extra.y.
float4 draw_template_fish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    float tailward = 1.0 - smoothstep(-0.9, 0.4, p.x);
    p.y -= sin(phase - p.x * 2.5) * 0.06 * tailward;
    float2 bc = float2(0.08, 0.0);
    float2 br = float2(0.58, 0.3 - 0.06 * smoothstep(0.0, 0.6, p.x));
    float body = (length((p - bc) / br) - 1.0) * 0.28;
    float stock = sd_seg(p, float2(-0.35, 0.0), float2(-0.62, 0.0)) - 0.06;
    body = smin_k(body, stock, 0.08);
    float flap = sin(phase) * 0.06;
    float tail = sd_tri(p, float2(-0.6, 0.0), float2(-0.98, 0.32 + flap), float2(-0.98, -0.32 + flap)) - 0.02;
    tail = max(tail, -(length(p - float2(-1.05, flap)) - 0.16));   // forked
    float dorsal = sd_tri(p, float2(-0.35, 0.18), float2(0.3, 0.22), float2(-0.05, 0.42 + 0.02 * sin(phase * 2.0))) - 0.01;
    float anal = sd_tri(p, float2(-0.35, -0.12), float2(0.0, -0.2), float2(-0.25, -0.34)) - 0.01;
    float pect = sd_tri(p, float2(0.25, -0.05), float2(0.05, -0.2 + 0.03 * sin(phase * 1.5)), float2(0.0, -0.05)) - 0.01;
    float fins = min(min(tail, dorsal), anal);
    float d = min(body, fins);
    float aa = fwidth(d) + 1e-4;
    float a = (1.0 - smoothstep(-aa, aa, d)) * col.a;
    if (a <= 0.0) return float4(0.0);

    float3 L = normalize(float3(-0.3, 0.8, 0.5));
    float3 c3;
    int pat = int(extra.y + 0.5) % 4;
    if (body <= fins) {
        float2 q = (p - bc) / float2(0.6, 0.32);
        float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))));
        float lit = 0.55 + 0.55 * max(0.0, dot(n, L));
        c3 = col.rgb * lit;
        c3 = mix(c3, mix(col.rgb, float3(1.0), 0.55), smoothstep(-0.05, -0.25, p.y) * 0.5);   // pale belly
        // patterns
        if (pat == 1) c3 = mix(c3, col.rgb * 0.35, smoothstep(0.1, 0.0, abs(fract(p.x * 3.5 + 0.2) - 0.5) - 0.18) * 0.7);
        else if (pat == 2) c3 = mix(c3, col.rgb * 0.4, smoothstep(0.5, 0.62, vnoise(p * 5.0 + 3.1) * 0.65 + vnoise(p * 11.0) * 0.35) * 0.6 * step(-0.05, p.y));
        else if (pat == 3) c3 = mix(c3, float3(1.0), smoothstep(0.06, 0.0, abs(p.y + 0.02 - 0.05 * sin(p.x * 3.0)) - 0.02) * 0.6);
        // scales, subtle
        c3 *= 1.0 - 0.12 * smoothstep(0.05, 0.0, vor_edge(p * 14.0));
        // gill line
        c3 = mix(c3, col.rgb * 0.45, smoothstep(0.02, 0.0, abs(length((p - float2(0.6, 0.0)) / float2(1.0, 1.4)) - 0.22)) * step(abs(p.y), 0.2) * 0.6);
        // rim on top, dark line on the bottom
        c3 += mix(col.rgb, float3(1.0), 0.5) * smoothstep(-0.04, 0.0, body) * step(0.0, p.y) * 0.35;
        c3 *= 1.0 - 0.35 * smoothstep(-0.04, 0.0, body) * step(p.y, 0.0);
        c3 += 0.35 * pow(max(0.0, dot(reflect(-L, n), float3(0, 0, 1))), 20.0);
        // pectoral fin over the body
        c3 = mix(c3, mix(col.rgb * 0.8, float3(1.0), 0.2), smoothstep(0.01, -0.01, pect) * 0.35);
    } else {
        // fins: see-through, lighter toward the edge, with rays
        float edge = smoothstep(-0.08, 0.0, fins);
        c3 = mix(col.rgb * 0.8, mix(col.rgb, float3(1.0), 0.5), edge);
        float rays = smoothstep(0.3, 0.0, abs(fract(atan2(p.y, p.x + 0.2) * 9.0) - 0.5));
        c3 *= 1.0 - 0.2 * rays;
        a *= 0.82;
    }
    // eye
    float2 eye = float2(0.5, 0.07);
    if (extra.w > 1.5) {
        c3 = mix(c3, col.rgb * 0.25, smoothstep(0.012, 0.0, abs(p.y - eye.y + 0.01 * (p.x - eye.x)) - 0.008) * step(abs(p.x - eye.x), 0.055));
    } else {
        float er = length(p - eye);
        c3 = mix(c3, float3(0.95, 0.9, 0.7), smoothstep(0.065, 0.05, er));
        c3 = mix(c3, float3(0.02), smoothstep(0.038, 0.028, er));
        c3 = mix(c3, float3(1.0), smoothstep(0.014, 0.006, length(p - eye - float2(0.012, 0.014))));
    }
    c3 += col.rgb * glow * 0.45;
    // halo when glowing (fades before the quad edge)
    float r2 = dot((p - bc) / float2(0.85, 0.55), (p - bc) / float2(0.85, 0.55));
    float halo = glow * (exp(-r2 * 3.0) * 0.25) * smoothstep(1.0, 0.8, max(abs(c.x), abs(c.y))) * col.a;
    float3 rgb = c3 * a + col.rgb * halo * (1.0 - a);
    return float4(rgb, a + halo * (1.0 - a) * 0.6);
}
