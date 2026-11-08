// A sea angel (Clione): a small translucent body with a glowing orange heart, flapping two wing-like lobes as it
// "flies" through the water — the arctic's music fish. Its heart takes a little of the song's color (col).
float4 draw_arctic_sea_angel(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    // it swims head first (+x): the body is a soft teardrop along x
    float body = (length((p - float2(0.05, 0.0)) / float2(0.7, 0.22 * mix(0.35, 1.0, smoothstep(-0.6, 0.3, p.x)))) - 1.0) * 0.2;
    float head = (length((p - float2(0.68, 0.0)) / float2(0.2, 0.17)) - 1.0) * 0.17;
    body = smin_k(body, head, 0.06);
    // the wings: two lobes near the head, flapping up and down
    float flap = sin(phase * 3.0);
    float wings = 1e3;
    for (int k = -1; k <= 1; k += 2) {
        float fk = float(k);
        // one lobe above, one below, flapping together (like wings seen from the side)
        float lift = fk * (0.26 + 0.1 * flap);
        float2 q = p - float2(0.42 - 0.06 * flap, lift);
        float ang = fk * (0.35 - 0.4 * flap);
        q = float2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
        wings = min(wings, (length(q / float2(0.15, 0.22)) - 1.0) * 0.15);
    }
    float d = min(body, wings);
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    // glassy: almost clear, bright at the rims; an orange-red heart and gut glowing inside
    float rim = 1.0 - smoothstep(0.0, 0.04, -d);
    float3 glass = float3(0.75, 0.88, 1.0);
    float3 c3 = glass * (0.35 + 0.8 * rim);
    float alpha = 0.3 + 0.55 * rim;
    float heart = exp(-dot((p - float2(0.1, 0.0)) / float2(0.3, 0.1), (p - float2(0.1, 0.0)) / float2(0.3, 0.1)) * 2.0);
    float3 core = mix(float3(1.0, 0.45, 0.15), col.rgb, 0.25);
    float pulse = 0.8 + 0.2 * sin(phase * 2.0);
    c3 = mix(c3, core * (1.0 + glow * 0.6), heart * 0.85 * pulse);
    alpha = max(alpha, heart * 0.9);
    c3 = mix(c3, core * 0.8, (1.0 - smoothstep(0.04, 0.06, length(p - float2(0.74, 0.04)))) * 0.8);   // the little head spot
    float aOut = a * alpha * col.a;
    float edge = 1.0 - smoothstep(0.55, 1.0, max(abs(c.x), abs(c.y)));
    float halo = (glow * 0.8 + 0.15) * exp(-max(d, 0.0) * 9.0) * edge * (1.0 - a);
    return float4(c3 * aOut + core * halo * 0.6, aOut + halo * 0.35);
}
