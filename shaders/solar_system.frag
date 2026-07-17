#version 460 core

// Solar system showcase — Sun + Earth + Moon, analytic ray-traced spheres,
// plus a Milky Way band, shooting stars, a periodic comet, orbit guides,
// an asteroid belt and a screen-space lens flare. The whole scene lives in
// this one fragment shader (Shadertoy-style), driven from Dart with time +
// camera uniforms; precompiled by Impeller. Everything is deterministic
// from uTime — no extra uniforms needed.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;    // canvas size in px
uniform float uTime;   // seconds since screen opened
uniform float uYaw;    // camera yaw (radians)
uniform float uPitch;  // camera pitch (radians)
uniform float uDist;   // camera distance from origin

out vec4 fragColor;

// ---------- noise ----------

float hash1(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash11(float n) {
  return fract(sin(n) * 43758.5453);
}

float noise3(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
      mix(mix(hash1(i + vec3(0, 0, 0)), hash1(i + vec3(1, 0, 0)), f.x),
          mix(hash1(i + vec3(0, 1, 0)), hash1(i + vec3(1, 1, 0)), f.x), f.y),
      mix(mix(hash1(i + vec3(0, 0, 1)), hash1(i + vec3(1, 0, 1)), f.x),
          mix(hash1(i + vec3(0, 1, 1)), hash1(i + vec3(1, 1, 1)), f.x), f.y),
      f.z);
}

float fbm(vec3 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise3(p);
    p = p * 2.03 + vec3(1.7);
    a *= 0.5;
  }
  return v;
}

// Cheaper 3-octave variant for secondary detail.
float fbm3(vec3 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * noise3(p);
    p = p * 2.03 + vec3(1.7);
    a *= 0.5;
  }
  return v;
}

// ---------- geometry ----------

// Ray-sphere: returns nearest positive t, or -1.
float iSphere(vec3 ro, vec3 rd, vec3 c, float r) {
  vec3 oc = ro - c;
  float b = dot(oc, rd);
  float h = b * b - dot(oc, oc) + r * r;
  if (h < 0.0) return -1.0;
  float t = -b - sqrt(h);
  return t > 0.0 ? t : -1.0;
}

vec3 rotY(vec3 p, float a) {
  float s = sin(a), c = cos(a);
  return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// ---------- background ----------

vec3 skyBackground(vec3 rd, float tt) {
  vec3 col = vec3(0.0);

  // Milky Way: elongated cloudy band along a tilted great circle,
  // with darker dust lanes threaded through it.
  vec3 mwN = normalize(vec3(0.42, 0.86, 0.28));
  float band = dot(rd, mwN);
  float bandMask = exp(-band * band * 18.0);
  float cloud = fbm3(rd * 3.1 + vec3(7.3));
  float dust = fbm3(rd * 6.4 - vec3(2.9));
  vec3 mw = (vec3(0.75, 0.72, 0.85) * cloud * cloud * 1.6 +
             vec3(0.35, 0.45, 0.75) * cloud * 0.5) *
            bandMask;
  mw *= 1.0 - 0.75 * smoothstep(0.45, 0.75, dust) * bandMask;
  col += mw * 0.55;

  // Faint wide nebula washes outside the band.
  col += vec3(0.012, 0.020, 0.050) * fbm3(rd * 2.2 + vec3(3.1)) * 2.0;
  col += vec3(0.030, 0.010, 0.045) * fbm3(rd * 3.7) * 0.8;

  // Two layers of jittered point stars, with color temperature + twinkle.
  for (int layer = 0; layer < 2; layer++) {
    float scale = layer == 0 ? 60.0 : 130.0;
    vec3 d = rd * scale;
    vec3 id = floor(d);
    vec3 jitter = vec3(hash1(id), hash1(id + 7.1), hash1(id + 13.7));
    vec3 q = fract(d) - 0.5 - (jitter - 0.5) * 0.8;
    float m = hash1(id + 3.3);
    float star = smoothstep(0.10, 0.0, length(q)) * step(0.90, m);
    star *= 0.55 + 0.45 * sin(tt * (1.0 + m * 3.0) + m * 40.0);
    float temp = hash1(id + 5.9);
    vec3 tint = mix(vec3(1.0, 0.82, 0.62), vec3(0.68, 0.80, 1.0), temp);
    col += tint * star * (layer == 0 ? 1.0 : 0.55) * (1.0 + bandMask * 0.8);
  }

  // Occasional shooting star.
  float cyc = floor(tt / 9.0);
  float ph = fract(tt / 9.0) / 0.13;
  if (ph < 1.0) {
    float az = hash11(cyc * 13.7) * 6.2831;
    float el = hash11(cyc * 7.9 + 2.0) * 1.4 - 0.7;
    vec3 p0 = vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
    vec3 tang = normalize(cross(p0, vec3(0.31, 0.9, 0.27)));
    vec3 head = normalize(p0 + tang * ph * 0.5);
    vec3 prev = normalize(p0 + tang * (ph - 0.06) * 0.5);
    vec3 tdir = normalize(prev - head + vec3(1e-4));
    vec3 dvec = rd - head;
    float along = dot(dvec, tdir);
    float lat = length(dvec - tdir * along);
    float env = sin(3.14159 * ph);
    float headG = exp(-dot(dvec, dvec) * 4200.0) * 1.6;
    float tailG = exp(-lat * 260.0) * exp(-max(along, 0.0) * 26.0) *
                  step(0.0, along) * 0.7;
    col += vec3(0.85, 0.92, 1.0) * (headG + tailG) * env *
           step(0.2, dot(rd, head));
  }

  return col;
}

// ---------- main ----------

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = (2.0 * frag - uSize) / uSize.y;
  uv.y = -uv.y;  // canvas y grows downward

  // Camera orbiting the origin.
  float cp = cos(uPitch), sp = sin(uPitch);
  float cy = cos(uYaw), sy = sin(uYaw);
  vec3 ro = uDist * vec3(cp * sy, sp, cp * cy);
  vec3 ww = normalize(-ro);
  vec3 uu = normalize(cross(vec3(0.0, 1.0, 0.0), ww));
  vec3 vv = cross(ww, uu);
  vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.7 * ww);

  // Scene layout.
  const float SUN_R = 1.0;
  const float EARTH_R = 0.34;
  const float MOON_R = 0.10;
  const float ORBIT_R = 2.7;

  float ea = uTime * 0.15;  // Earth orbital angle
  vec3 earthC = ORBIT_R * vec3(cos(ea), 0.0, sin(ea));
  float ma = uTime * 0.9;  // Moon orbital angle
  vec3 moonC = earthC + 0.62 * vec3(cos(ma), 0.18 * sin(ma * 0.7), sin(ma));

  // Trace all three; nearest hit wins.
  float tSun = iSphere(ro, rd, vec3(0.0), SUN_R);
  float tEarth = iSphere(ro, rd, earthC, EARTH_R);
  float tMoon = iSphere(ro, rd, moonC, MOON_R);

  float t = 1e9;
  int hit = 0;  // 0 none, 1 sun, 2 earth, 3 moon
  if (tSun > 0.0 && tSun < t) { t = tSun; hit = 1; }
  if (tEarth > 0.0 && tEarth < t) { t = tEarth; hit = 2; }
  if (tMoon > 0.0 && tMoon < t) { t = tMoon; hit = 3; }

  vec3 col;

  if (hit == 0) {
    col = skyBackground(rd, uTime);
  } else if (hit == 1) {
    // --- Sun: domain-warped plasma ---
    vec3 p = ro + t * rd;
    vec3 n = normalize(p);
    vec3 q = rotY(n, uTime * 0.05);
    float warp = fbm3(q * 2.3 + vec3(0.0, uTime * 0.10, 0.0));
    float plasma = fbm(q * 3.5 + vec3(warp * 1.5) +
                       vec3(0.0, 0.0, uTime * 0.13));
    plasma += 0.45 * fbm3(q * 9.0 - vec3(uTime * 0.22));
    plasma *= 0.75;
    vec3 hot = vec3(1.30, 1.05, 0.55);
    vec3 mid = vec3(1.05, 0.45, 0.08);
    vec3 dark = vec3(0.55, 0.12, 0.01);
    col = mix(dark, mid, smoothstep(0.15, 0.55, plasma));
    col = mix(col, hot, smoothstep(0.55, 0.85, plasma));
    // White-hot convection cells.
    col += vec3(1.5, 1.2, 0.75) * smoothstep(0.80, 0.98, plasma);
    // Limb brightening for a fiery edge.
    float rim = pow(1.0 - abs(dot(n, -rd)), 2.0);
    col += vec3(1.0, 0.55, 0.15) * rim * 1.1;
  } else if (hit == 2) {
    // --- Earth ---
    vec3 p = ro + t * rd;
    vec3 n = normalize(p - earthC);
    vec3 L = normalize(-earthC);  // sunlight from origin
    float diff = max(dot(n, L), 0.0);

    // Surface in spin-rotated coords.
    vec3 s = rotY(n, uTime * 0.35);
    float cont = fbm(s * 2.6 + vec3(11.0));
    float landM = smoothstep(0.50, 0.54, cont);
    // Shallow shelf water glows lighter near the coastlines.
    float coast = smoothstep(0.44, 0.50, cont) * (1.0 - landM);
    vec3 ocean = mix(vec3(0.015, 0.10, 0.30), vec3(0.03, 0.22, 0.38), coast);
    vec3 land = mix(vec3(0.05, 0.24, 0.07), vec3(0.38, 0.30, 0.13),
                    smoothstep(0.55, 0.75, cont));
    land = mix(land, vec3(0.20, 0.26, 0.10),
               smoothstep(0.60, 0.68, fbm3(s * 5.0 + vec3(4.0))));
    // Polar ice caps.
    float ice = smoothstep(0.72, 0.85, abs(n.y));
    vec3 surf = mix(ocean, land, landM);
    surf = mix(surf, vec3(0.85, 0.90, 0.95), ice);

    // Clouds drift separately; a light-offset sample casts soft shadows.
    vec3 cs = rotY(n, uTime * 0.25) * 4.5 + vec3(31.0);
    float cl = fbm(cs);
    float clShadow = fbm3(cs + L * 0.35);
    surf *= 1.0 - 0.22 * smoothstep(0.55, 0.75, clShadow);
    surf = mix(surf, vec3(0.95), smoothstep(0.58, 0.75, cl) * 0.85);

    // Day/night with a soft terminator; sharp glint on open water.
    float day = smoothstep(-0.08, 0.25, dot(n, L));
    vec3 spec = vec3(1.0, 0.98, 0.90) *
                pow(max(dot(reflect(-L, n), -rd), 0.0), 90.0) *
                (1.0 - landM) * (1.0 - smoothstep(0.58, 0.75, cl)) *
                day * 0.9;
    col = surf * (0.03 + 0.97 * diff) + spec;

    // City lights on the night side.
    float night = 1.0 - day;
    float city = step(0.965, noise3(s * 40.0)) * landM * night;
    col += vec3(1.0, 0.75, 0.35) * city * 0.8;

    // Aurora ovals near the poles, dancing on the night side.
    float aurBand = smoothstep(0.52, 0.62, abs(n.y)) *
                    (1.0 - smoothstep(0.70, 0.80, abs(n.y)));
    float aur = aurBand * night *
                (0.4 + 0.6 * fbm3(s * 5.0 + vec3(0.0, uTime * 0.45, 0.0)));
    col += vec3(0.15, 0.95, 0.55) * aur * 0.9;
    col += vec3(0.45, 0.35, 0.95) * aur * aur * 0.5;

    // Atmosphere rim (fresnel).
    float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
    col += vec3(0.25, 0.55, 1.0) * fres * (0.25 + 0.75 * day);
  } else {
    // --- Moon ---
    vec3 p = ro + t * rd;
    vec3 n = normalize(p - moonC);
    vec3 L = normalize(-moonC);
    float diff = max(dot(n, L), 0.0);
    float rock = fbm(n * 6.0 + vec3(5.0));
    // Crater-ish dark patches.
    rock -= 0.25 * smoothstep(0.55, 0.75, fbm(n * 3.0 + vec3(9.0)));
    vec3 surf = vec3(0.55, 0.54, 0.52) * (0.5 + 0.8 * rock);
    col = surf * (0.04 + 0.96 * diff);
  }

  // --- Ecliptic-plane extras: orbit guides + asteroid belt ---
  if (abs(rd.y) > 1e-4) {
    float tp = -ro.y / rd.y;
    if (tp > 0.0 && tp < t) {
      vec3 pp = ro + tp * rd;
      float rr = length(pp.xz);
      float fade = exp(-tp * 0.045);
      float ang = atan(pp.z, pp.x);

      // Earth orbit guide, gently dashed and drifting.
      float g1 = exp(-abs(rr - ORBIT_R) * 26.0);
      float dash = 0.65 + 0.35 * sin(ang * 60.0 - uTime * 0.8);
      col += vec3(0.35, 0.75, 0.95) * g1 * 0.15 * dash * fade;

      // Moon orbit guide around Earth.
      float rm = length(pp.xz - earthC.xz);
      float g2 = exp(-abs(rm - 0.62) * 60.0);
      col += vec3(0.60, 0.70, 0.95) * g2 * 0.10 * fade;

      // Asteroid belt: slowly rotating ring of sparkling dust.
      float belt = smoothstep(3.45, 3.75, rr) *
                   (1.0 - smoothstep(4.05, 4.35, rr));
      if (belt > 0.002) {
        float ba = ang + uTime * 0.02;
        vec3 bp = vec3(cos(ba) * rr, 0.0, sin(ba) * rr);
        float rocks = noise3(bp * 7.0);
        float sparkle = smoothstep(0.80, 0.97, rocks);
        float dustF = fbm3(bp * 2.1) * 0.5;
        col += (vec3(0.85, 0.80, 0.72) * sparkle * 0.55 +
                vec3(0.30, 0.27, 0.24) * dustF) *
               belt * fade * 0.8;
      }
    }
  }

  // --- Comet: elliptical pass every ~26 s with a curved dust tail ---
  {
    float ca = 6.2831 * uTime / 26.0;
    float ecc = 0.60;
    float crr = 3.6 * (1.0 - ecc * ecc) / (1.0 + ecc * cos(ca));
    vec3 cflat = vec3(cos(ca), 0.0, sin(ca)) * crr;
    float ctilt = 0.45;
    vec3 cpos = vec3(cflat.x, -sin(ctilt) * cflat.z, cos(ctilt) * cflat.z);
    float bC = dot(cpos - ro, rd);
    bool cometOccluded = hit != 0 && bC > t;
    if (bC > 0.0 && !cometOccluded) {
      vec3 tailDir = normalize(cpos);  // dust pushed away from the sun
      vec3 vel = vec3(-sin(ca), 0.0, cos(ca));
      vec3 velDir = vec3(vel.x, -sin(ctilt) * vel.z, cos(ctilt) * vel.z);
      float tail = 0.0;
      for (int i = 0; i < 9; i++) {
        float fi = float(i) / 8.0;
        vec3 sp = cpos + tailDir * fi * 1.5 - velDir * fi * fi * 0.45;
        float bS = dot(sp - ro, rd);
        vec3 cq = ro + rd * max(bS, 0.0) - sp;
        float d2 = dot(cq, cq);
        float w = 1.0 - fi;
        tail += exp(-d2 * mix(60.0, 900.0, w * w)) * w * w * 0.35;
      }
      vec3 hcp = ro + rd * bC - cpos;
      float hd2 = dot(hcp, hcp);
      col += vec3(0.85, 0.95, 1.0) * exp(-hd2 * 1400.0) * 1.6;  // head core
      col += vec3(0.55, 0.75, 1.0) * exp(-hd2 * 160.0) * 0.5;   // head glow
      col += vec3(0.45, 0.65, 1.0) * tail;
    }
  }

  // --- Sun corona: additive glow + animated streamers around the disc ---
  float bSun = -dot(ro, rd);
  float dClose = length(ro + rd * max(bSun, 0.0));
  bool sunBehindHit =
      hit != 0 && hit != 1 && bSun > t;  // occluder in front of the sun
  if (!sunBehindHit && bSun > 0.0) {
    float glow = exp(-(dClose - SUN_R) * 2.2);
    glow = clamp(glow, 0.0, 1.0);
    vec3 cdir = normalize(ro + rd * max(bSun, 0.0));
    float streak =
        0.70 + 0.30 * fbm3(cdir * 6.0 + vec3(0.0, uTime * 0.30, 0.0));
    col += vec3(1.0, 0.55, 0.18) * glow * glow * 0.9 * streak;
    col += vec3(1.0, 0.85, 0.55) * pow(glow, 6.0) * 0.8;
    // Wide, faint outer halo.
    col += vec3(1.0, 0.55, 0.20) * exp(-(dClose - SUN_R) * 0.8) * 0.10;
  }

  // --- Screen-space lens flare when the sun is in view ---
  vec3 sunDir = normalize(-ro);
  float fw = dot(sunDir, ww);
  if (fw > 0.05) {
    vec2 sunUV = 1.7 * vec2(dot(sunDir, uu), dot(sunDir, vv)) / fw;
    float occF = 1.0;
    if (iSphere(ro, sunDir, earthC, EARTH_R) > 0.0) occF = 0.10;
    if (iSphere(ro, sunDir, moonC, MOON_R) > 0.0) occF = min(occF, 0.25);
    float edge = smoothstep(2.4, 1.0, length(sunUV));
    vec2 duv = uv - sunUV;
    float streakA = exp(-abs(duv.y) * 30.0) * exp(-abs(duv.x) * 2.4) * 0.12;
    float halo = exp(-length(duv) * 3.2) * 0.08;
    float ghosts = 0.0;
    for (int i = 0; i < 4; i++) {
      float gk = -0.55 + float(i) * 0.37;
      vec2 gp = sunUV * gk;
      float gr = 0.045 + float(i) * 0.022;
      ghosts += smoothstep(gr, gr * 0.5, length(uv - gp)) *
                (0.030 + 0.012 * float(i));
    }
    col += (vec3(1.0, 0.85, 0.60) * (streakA + halo) +
            vec3(0.55, 0.80, 1.0) * ghosts) *
           occF * edge;
  }

  // Filmic-ish tone curve + gentle vignette.
  col = col / (1.0 + col * 0.35);
  col = pow(max(col, 0.0), vec3(0.90));
  float vig = 1.0 - 0.25 * dot(uv * 0.55, uv * 0.55);
  col *= vig;

  fragColor = vec4(col, 1.0);
}
