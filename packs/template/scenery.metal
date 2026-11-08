// Scenery: float4 draw_<name>(float2 c, float t, float glow, float4 col, float4 extra)
//   c      -1…1 over the quad (its "extent" × its size), y up. On the sand, c.y = -1 is the sand line.
//   t      seconds, for anything that moves
//   glow   0…1: rises at night when "glowAtNight" is on
//   col    its color, already lit by the hour
//   extra  y: a seed (0…1, different for each copy), w: how dark the night is (0…1)
// The shader's helpers can be used: sd_box, sd_seg, sd_tri, smin_k, vnoise, hash21, vor_edge.
float4 draw_template_scenery(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.0, 0.8);                                              // square units: c × extent
    // a rounded rock sitting on the sand (c.y = -1), with a crystal growing out of it
    float2 rq = (p - float2(0.0, -0.42)) / float2(0.85, 0.5);
    float rock = (length(rq) - 1.0 - 0.06 * (vnoise(p * 4.0 + extra.y * 9.0) - 0.5)) * 0.5;
    rock = max(rock, -(p.y + 0.8));                                               // flat where it meets the sand
    float crystal = sd_tri(p, float2(-0.13, -0.15), float2(0.13, -0.15), float2(0.03 + 0.1 * (extra.y - 0.5), 0.72)) - 0.02;
    float d = min(rock, crystal);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 L = normalize(float3(-0.3, 0.8, 0.5));
    float3 c3;
    if (crystal < rock) {
        // glassy: lit on one face, a bright edge, glowing from inside at night
        float face = step(0.03 + 0.1 * (extra.y - 0.5) * (p.y + 0.15) / 0.87, p.x);
        c3 = mix(float3(0.45, 0.75, 0.95), float3(0.8, 0.95, 1.0), smoothstep(-0.15, 0.7, p.y)) * (0.75 + 0.3 * face);
        c3 += float3(0.6, 0.9, 1.0) * glow * (0.6 + 0.4 * sin(t * 1.5 + extra.y * 20.0));
    } else {
        // stone: a fake normal from the ellipse, light from above, patchy texture, moss on top
        float3 n = normalize(float3(rq, sqrt(max(0.02, 1.0 - dot(rq, rq)))));
        c3 = col.rgb * (0.4 + 0.75 * max(0.0, dot(n, L))) * (0.85 + 0.3 * vnoise(p * 9.0 + extra.y * 10.0));
        c3 = mix(c3, float3(0.3, 0.45, 0.25) * dot(col.rgb, float3(0.9)), smoothstep(0.55, 0.75, n.y + 0.3 * vnoise(p * 6.0)) * 0.5);
        c3 *= 0.6 + 0.4 * smoothstep(-0.8, -0.55, p.y);                          // shadowed at the sand
        c3 += float3(0.4, 0.75, 0.9) * glow * 0.25 * exp(-max(crystal, 0.0) * 12.0);   // the crystal's light on the stone
    }
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;                          // a darker outline
    return float4(c3 * a, a);
}
