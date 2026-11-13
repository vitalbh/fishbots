/// What every stage shares: the uniforms, the theme, a sprite, noise and the caustics.
let shaderCommon = #"""
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
    float4 flashColor; // the lightning's color (the plugin's or the theme's)
    float4 lamps[4];   // lamps in the water (Fauna.lamps): xy in points, z how far the light reaches, w how strong
    float4 lampColors[4];
};

// The lamps' light falling on a point (in points): what's around a lanternfish's lure takes its color.
float3 lamp_light(float2 p, constant Uniforms& u) {
    float3 l = float3(0.0);
    for (int i = 0; i < 4; i++) {
        if (u.lamps[i].w < 0.002) continue;
        float2 d = (p - u.lamps[i].xy) / u.lamps[i].z;
        l += u.lampColors[i].rgb * (u.lamps[i].w * exp(-dot(d, d) * 2.2));
    }
    return min(l, float3(1.3));                                        // several together don't burn it out
}

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
    float4 pack;       // x: the pack background's index + 1 (0: none), y: it replaces the distant reef, z: no floor, w: no surface
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

"""#
