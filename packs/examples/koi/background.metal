// The pond's far side: mossy boulders along the bottom and tall reeds rising into the haze, swaying slowly.
// (It replaces the coral reef the aquarium draws in the distance.)
float4 draw_koi_background(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {
    float aspect = extra.x;
    float x = uv.x + gaze.x * 0.004;                                    // far away: barely any parallax
    float3 haze = water;
    float3 moss = mix(water, float3(0.25, 0.38, 0.2) * (0.4 + 0.6 * light), 0.45);
    float3 rock = mix(water, float3(0.16, 0.2, 0.18) * (0.4 + 0.6 * light), 0.5);
    float3 reedC = mix(water, float3(0.2, 0.34, 0.16) * (0.4 + 0.6 * light), 0.55);
    float4 out = float4(0.0);
    // reeds: thin blades, each its own height and sway, the far ones fainter
    for (int k = 0; k < 18; k++) {
        float fk = float(k);
        float x0 = fract(sin(fk * 91.7) * 4375.85) * 1.1 - 0.05;
        if (abs(x - x0) > 0.05) continue;
        float h = 0.28 + 0.3 * fract(sin(fk * 17.3) * 913.1);
        float yy = uv.y - extra.z + 0.01;
        if (yy < 0.0 || yy > h) continue;
        float tt = yy / h;
        float sway = sin(t * 0.35 + fk * 1.7) * 0.012 * tt * tt;
        float dx = (x - x0 - sway) * aspect;
        float w = 0.0028 * (1.0 - 0.8 * tt);
        float blade = 1.0 - smoothstep(w * 0.4, w, abs(dx));
        float far = 0.45 + 0.4 * fract(fk * 0.37);
        float3 c = mix(reedC, haze, 1.0 - far) * (0.85 + 0.25 * tt);
        out = mix(out, float4(c, 1.0) * far, blade * far);
    }
    // boulders along the bottom, rounded, with moss on their tops
    float h = extra.z + 0.05 + 0.05 * vnoise(float2(x * 3.5, 1.7)) + 0.03 * vnoise(float2(x * 11.0, 4.2));
    h += 0.05 * smoothstep(0.12, 0.0, abs(x - 0.18)) + 0.06 * smoothstep(0.14, 0.0, abs(x - 0.72));
    if (uv.y < h) {
        float top = smoothstep(h - 0.03, h, uv.y);
        float3 c = mix(rock, moss, top * 0.8) * (0.85 + 0.25 * vnoise(float2(x * 30.0, uv.y * 30.0)));
        out = float4(c, 1.0) * 0.75 + out * 0.25;
    }
    return out;
}
