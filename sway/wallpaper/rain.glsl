//!HOOK OUTPUT
//!BIND HOOKED
//!DESC rain, drifting fog and water ripples over the wallpaper photo

// Photo-specific: screen height (0 = bottom, 1 = top) of the far shoreline.
// Below it, raindrops ripple the water. Set to 0.0 for photos without water.
#define WATER_LINE 0.22

#define FOG_COLOR vec3(0.70, 0.75, 0.77)
// Drops pick up the overcast sky: lighter than dark trees, darker than fog.
#define RAIN_COLOR vec3(0.60, 0.64, 0.67)

// ---------------------------------------------------------------- noise

// Sin-free hash (Dave Hoskins); sin() hashes collapse at low precision.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i),                  hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    const mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);  // rotate octaves to hide the grid
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = rot * p * 2.03;
        a *= 0.5;
    }
    return v;
}

// ---------------------------------------------------------------- time
//
// `frame` counts up forever and floats lose precision as it grows, so every
// clock here wraps. Rain wraps exactly (no visible seam); fog and wind drift
// on a 10-hour clock and jump once when it wraps.

float slowTime() {
    return float(frame % 1080000) / 30.0;
}

// Rain scroll offset in cells, wrapped at 4096 cells. speed is cells/sec.
float rainScroll(int speed) {
    int f = frame % 122880;                      // 122880 frames = 30 * 4096
    return float((f * speed) % 122880) / 30.0;
}

// ---------------------------------------------------------------- rain

// One sheet of rain streaks. uv is y-up in screen-height units; scale = cell
// grid (narrow, tall), len = streak length within a cell, thick = width in
// pixels, density = fraction of cells holding a drop.
float rain(vec2 uv, vec2 scale, int speed, float len, float thick,
           float slant, float density, float seed) {
    vec2 p = uv;
    p.x += p.y * slant;
    p *= scale;
    p.y += rainScroll(speed);
    vec2 cell = floor(p);
    cell.y = mod(cell.y, 4096.0);                // matches the scroll wrap
    vec2 f = fract(p);
    if (hash12(cell + seed) > density) return 0.0;
    float xoff = 0.15 + 0.7 * hash12(cell + seed + 17.0);
    float yoff = hash12(cell + seed + 31.0) * (1.0 - len);
    float s = (f.y - yoff) / len;                // 0 at head (bottom), 1 at tail
    if (s < 0.0 || s > 1.0) return 0.0;
    float wpx = thick * scale.x / HOOKED_size.y;
    float line = smoothstep(wpx, 0.0, abs(f.x - xoff));
    return line * (1.0 - s) * smoothstep(0.0, 0.08, s);   // soft head, fading tail
}

// ---------------------------------------------------------------- ripples

// Rain rings on the water below WATER_LINE. Returns xy = gradient for
// refraction, z = crest brightness, w = trough darkness. grid sets ring size
// (bigger = smaller rings), density = fraction of cells with a ring, life =
// seconds per ring.
vec4 ripples(vec2 uv, float t, float grid, float density, float life, float seed) {
    float d = WATER_LINE - uv.y;                 // depth below the shoreline
    if (d <= 0.0) return vec4(0.0);
    // Project onto the water plane: cells shrink and squash toward the shore.
    vec2 q = vec2(uv.x, 1.0) * (2.75 / d) * grid;
    q.x *= 0.35;
    q += seed * 37.0;
    vec2 cell = floor(q);
    vec4 acc = vec4(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 c = cell + vec2(float(i), float(j));
        if (hash12(c * 1.7 + seed) > density) continue;
        vec2 centre = c + vec2(hash12(c + 3.1), hash12(c + 7.7));
        float period = life * (0.7 + 0.6 * hash12(c + 11.3));
        float age = fract(t / period + hash12(c + 5.9));
        float radius = age * 0.9;
        vec2 dv = q - centre;
        float dist = length(dv);
        float band = (dist - radius) * 9.0;
        float env = exp(-band * band) * (1.0 - age) * (1.0 - age);
        float wave = sin(band * 3.0);
        acc.xy += normalize(dv + 1e-4) * wave * env;
        acc.z += max(wave, 0.0) * env;
        acc.w += max(-wave, 0.0) * env;
    }
    float fade = smoothstep(0.0, 0.04, d);       // vanish into the far shore
    return acc * fade;
}

// ---------------------------------------------------------------- main

vec4 hook() {
    float y = 1.0 - HOOKED_pos.y;                // 0 bottom, 1 top
    vec2 uv = vec2(HOOKED_pos.x * HOOKED_size.x / HOOKED_size.y, y);
    float t = slowTime();

    // Wind: slow gusts swell the rain and lean it over.
    float gust = smoothstep(0.25, 0.75, noise(vec2(t * 0.07, 3.0)));
    float slant = 0.10 + 0.14 * gust;
    float density = 0.40 + 0.25 * gust;

    // Ripples bend the photo's reflection before anything else is drawn.
    // Real rain on water reads as fine stippling: many tiny quick dimples,
    // with the odd bigger ring among them.
    vec4 rip = ripples(uv, t, 3.0, 0.70, 0.5, 0.0) * 0.6
             + ripples(uv, t, 1.0, 0.22, 1.6, 1.0);
    vec2 pos = HOOKED_pos + rip.xy * vec2(1.0, -1.0) * HOOKED_pt * 7.0;
    vec3 col = HOOKED_tex(pos).rgb;

    // How foggy the photo already is here: bright and washed out = mist.
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
    float misty = smoothstep(0.40, 0.75, lum) * (1.0 - smoothstep(0.06, 0.22, sat));

    // Far rain sits behind the fog, so draw it first and let the fog veil it.
    float far = 0.0;
    far += rain(uv, vec2(150.0, 10.0), 11, 0.30, 0.6, slant, density, 1.0) * 0.20;
    far += rain(uv, vec2(95.0, 7.0),    9, 0.34, 0.7, slant, density, 2.0) * 0.28;
    col = mix(col, RAIN_COLOR, far * (1.0 - 0.8 * misty));

    // Drifting fog: domain-warped noise sliding sideways, heavier low down.
    vec2 fp = uv * vec2(1.1, 2.4) + vec2(t * 0.015, 0.0);
    vec2 warp = vec2(fbm(fp * 1.3 + vec2(t * 0.020, 0.0)),
                     fbm(fp * 1.3 + vec2(5.2, -t * 0.018)));
    float wisp = fbm(fp * 1.6 + warp * 0.9 + vec2(t * 0.03, 0.0));
    float height = smoothstep(0.95, 0.35, y);
    // Thick wisps add fog; gaps between them thin the photo's own mist, so
    // the existing fog appears to roll rather than sit under a new layer.
    float thicken = smoothstep(0.50, 0.80, wisp);
    float thin = 1.0 - smoothstep(0.25, 0.50, wisp);
    vec3 clear = clamp((col - FOG_COLOR * 0.25) / 0.75, 0.0, 1.0);
    col = mix(col, clear, thin * misty * 0.45);
    col = mix(col, FOG_COLOR, thicken * height * (0.10 + 0.40 * misty));

    // A faster band of mist skimming the water.
    if (WATER_LINE > 0.0) {
        float band = smoothstep(WATER_LINE - 0.14, WATER_LINE - 0.02, y)
                   * smoothstep(WATER_LINE + 0.07, WATER_LINE - 0.01, y);
        float skim = fbm(vec2(uv.x * 2.0 + t * 0.05, y * 9.0));
        col = mix(col, FOG_COLOR, band * smoothstep(0.40, 0.75, skim) * 0.35);
    }

    // Grade: flat overcast light. Pull saturation down, cool it, darker overhead.
    col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 0.78);
    col *= vec3(0.90, 0.96, 1.0);
    col *= mix(1.0, 0.74, smoothstep(0.35, 1.0, y));

    // Ring crests catch the light, troughs fall into shadow.
    col += vec3(0.75, 0.80, 0.85) * rip.z * 0.16;
    col *= 1.0 - rip.w * 0.14;

    // Near rain is in front of the fog: bigger, softer, faster.
    float near = 0.0;
    near += rain(uv, vec2(55.0, 4.5),  7, 0.35, 0.9, slant, density, 3.0) * 0.30;
    near += rain(uv, vec2(30.0, 2.6),  6, 0.30, 1.3, slant, density * 0.8, 4.0) * 0.32;
    near += rain(uv, vec2(14.0, 1.3),  4, 0.25, 2.4, slant, density * 0.5, 5.0) * 0.20;
    col = mix(col, RAIN_COLOR, min(near, 1.0));

    return vec4(col, 1.0);
}
