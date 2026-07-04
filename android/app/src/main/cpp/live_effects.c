#include <stdint.h>

/* RGBA8888 per-pixel effects for the Live Editor demo.
 * effect: 0=brightness, 1=pixelate, 2=glitch. value: 0..100 intensity.
 * Deliberately plain C loops: the Kotlin channel path implements the exact
 * same algorithms, so the transports are compared on equal compute. */

static inline uint8_t clamp_u8(int32_t v) {
    return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

__attribute__((visibility("default")))
void apply_effect(const uint8_t* src, uint8_t* dst,
                  int32_t width, int32_t height,
                  int32_t effect, int32_t value) {
    if (effect == 0) { /* brightness: value 0..100 -> delta -50..+50 */
        const int32_t d = value - 50;
        const int32_t n = width * height;
        for (int32_t i = 0; i < n; i++) {
            const uint8_t* s = src + (int64_t)i * 4;
            uint8_t* o = dst + (int64_t)i * 4;
            o[0] = clamp_u8(s[0] + d);
            o[1] = clamp_u8(s[1] + d);
            o[2] = clamp_u8(s[2] + d);
            o[3] = s[3];
        }
    } else if (effect == 1) { /* pixelate: block size 1..64 */
        const int32_t block = 1 + (value * 63) / 100;
        for (int32_t y = 0; y < height; y++) {
            const int32_t by = (y / block) * block;
            for (int32_t x = 0; x < width; x++) {
                const int32_t bx = (x / block) * block;
                const uint8_t* s = src + ((int64_t)by * width + bx) * 4;
                uint8_t* o = dst + ((int64_t)y * width + x) * 4;
                o[0] = s[0]; o[1] = s[1]; o[2] = s[2]; o[3] = s[3];
            }
        }
    } else { /* glitch: RGB shift 0..30px + line displacement every 16th row */
        const int32_t shift = (value * 30) / 100;
        for (int32_t y = 0; y < height; y++) {
            int32_t rowOff = 0;
            if (shift > 0 && (y % 16) == 0) {
                rowOff = ((y * 31 + value) % (2 * shift + 1)) - shift;
            }
            for (int32_t x = 0; x < width; x++) {
                int32_t xs = x + rowOff;
                if (xs < 0) xs = 0;
                if (xs >= width) xs = width - 1;
                int32_t xr = xs + shift; if (xr >= width) xr = width - 1;
                int32_t xb = xs - shift; if (xb < 0) xb = 0;
                const uint8_t* srow = src + (int64_t)y * width * 4;
                uint8_t* o = dst + ((int64_t)y * width + x) * 4;
                o[0] = srow[xr * 4];
                o[1] = srow[xs * 4 + 1];
                o[2] = srow[xb * 4 + 2];
                o[3] = srow[xs * 4 + 3];
            }
        }
    }
}
