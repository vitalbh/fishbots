// A little roadside shrine (hokora) in place of the treasure chest: a stone base, a wooden house with vermilion posts,
// a curved roof, and sliding doors. As a replaced chest, extra.y is how open it is (the summary is showing): the doors
// slide apart and a warm light comes out (glow).
float4 draw_koi_shrine(float2 c, float t, float glow, float4 col, float4 extra) {
    float2 p = c;
    float open = clamp(extra.y, 0.0, 1.0);
    float base = sd_box(p - float2(0.0, -0.8), float2(0.62, 0.12), 0.03);
    float step2 = sd_box(p - float2(0.0, -0.63), float2(0.5, 0.06), 0.02);
    float house = sd_box(p - float2(0.0, -0.22), float2(0.4, 0.36), 0.02);
    // the roof: wide eaves curving up at the ends, a ridge on top
    float ry = p.y - 0.18;
    float eave = 0.78 + 0.1 * smoothstep(0.45, 0.8, abs(p.x));
    float roof = max(max(abs(p.x) - eave, -ry - 0.04 * smoothstep(0.4, 0.8, abs(p.x))), ry - 0.3 + 0.38 * pow(abs(p.x) / 0.8, 1.6));
    float ridge = sd_box(p - float2(0.0, 0.5), float2(0.22, 0.04), 0.02);
    float d = min(min(min(base, step2), house), min(roof, ridge));
    float aa = fwidth(d) + 1e-4;
    float a = 1.0 - smoothstep(-aa, aa, d);
    float3 wood = float3(0.42, 0.28, 0.18) * dot(col.rgb, float3(1.4));
    float3 vermilion = float3(0.78, 0.22, 0.14);
    float3 stone = float3(0.55, 0.55, 0.52) * (0.8 + 0.3 * vnoise(p * 9.0));
    float3 c3;
    if (min(base, step2) < min(house, min(roof, ridge))) {
        c3 = stone * (0.75 + 0.3 * smoothstep(-0.95, -0.55, p.y));
    } else if (house < min(roof, ridge)) {
        // posts at the corners, a beam, and the doors in between
        float post = step(0.32, abs(p.x));
        float beam = step(abs(p.y - 0.08), 0.04);
        c3 = mix(wood * (0.85 + 0.2 * vnoise(float2(p.x * 3.0, p.y * 40.0))), vermilion, max(post, beam));
        // the doors slide apart: in the gap, the warm light
        float gap = open * 0.26;
        float inDoor = step(abs(p.x), 0.3) * step(p.y, 0.04) * step(-0.56, p.y);
        float lit = inDoor * step(abs(p.x), gap);
        float3 door = wood * 1.15 * (0.9 + 0.1 * step(0.5, fract(p.y * 9.0)));          // lattice of the doors
        c3 = mix(c3, door, inDoor * (1.0 - post));
        float3 warm = float3(1.0, 0.78, 0.4) * (0.5 + 0.9 * glow) * (0.9 + 0.1 * sin(t * 5.0));
        c3 = mix(c3, warm, lit);
        c3 *= 0.75 + 0.3 * smoothstep(-0.6, 0.1, p.y);
    } else {
        // roof: dark tiles in rows, lighter on top, the ridge a little brighter
        float tiles = 0.85 + 0.15 * step(0.5, fract(p.x * 10.0));
        c3 = float3(0.22, 0.24, 0.28) * tiles * (0.7 + 0.5 * smoothstep(0.15, 0.5, p.y));
        c3 = mix(c3, float3(0.3, 0.42, 0.26), smoothstep(0.6, 0.8, vnoise(p * 6.0 + 2.0)) * 0.4);   // moss
        if (ridge < roof) c3 = float3(0.3, 0.32, 0.36);
    }
    // the light spilling out onto the stone when it's open
    c3 += float3(1.0, 0.75, 0.35) * open * glow * 0.25 * exp(-length((p - float2(0.0, -0.3)) / float2(0.4, 0.5)) * 2.5);
    c3 *= 1.0 - (1.0 - smoothstep(0.0, 0.03, -d)) * 0.3;
    return float4(c3 * a, a);
}
