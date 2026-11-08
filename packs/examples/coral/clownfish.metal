// A clownfish: an orange oval with three white bands edged in black, round fins and a little tail.
// Same conventions as the built-in fish: c is the sprite's local point (-1…1, already mirrored to face +x),
// col.rgb the fish's color (ignored here: clownfish are always orange), glow 0…1, and the result is premultiplied.
float4 draw_clownfish(float2 c, float phase, float glow, float4 col, float4 extra) {
    float2 p = c * float2(1.25, 0.8);
    float wag = sin(phase * 3.0) * 0.08;
    float2 q = float2(p.x - 0.08, p.y);
    float body = length(q / float2(0.62, 0.38)) - 1.0;
    float2 t = float2(p.x + 0.62, p.y - wag * (0.62 + p.x));                     // tail, swaying
    float tail = max(abs(t.y) - 0.05 - (-t.x) * 0.55, max(t.x, -t.x - 0.3));
    float fin = length((p - float2(0.0, 0.33)) / float2(0.22, 0.1)) - 1.0;       // dorsal fin
    float d = min(min(body * 0.3, tail), fin * 0.08);
    float aa = fwidth(d) + 1e-4;
    float inside = 1.0 - smoothstep(-aa, aa, d);

    float3 orange = float3(1.0, 0.45, 0.08);
    float3 c3 = orange * (0.75 + 0.35 * (1.0 - length(q) * 1.3));
    // three white bands with black edges
    for (int k = 0; k < 3; k++) {
        float x0 = 0.38 - float(k) * 0.42;
        float w = k == 1 ? 0.075 : 0.055;
        float b = abs(p.x - x0 - p.y * 0.12);
        c3 = mix(c3, float3(0.04), 1.0 - smoothstep(w + 0.012, w + 0.028, b));
        c3 = mix(c3, float3(0.97), 1.0 - smoothstep(w - 0.01, w + 0.005, b));
    }
    c3 = mix(c3, float3(0.03), 1.0 - smoothstep(0.03, 0.045, length(p - float2(0.5, 0.08))));   // eye
    c3 += orange * glow * 0.4;

    float a = inside * col.a;
    float fade = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
    float halo = exp(-max(d, 0.0) * 12.0) * glow * (1.0 - inside) * fade;
    return float4(c3 * a + orange * halo * 0.9, min(a + halo * 0.55, 1.0));
}
