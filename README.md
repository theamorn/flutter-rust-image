# flutter-rust-image

Benchmark demo: how fast can Flutter process images, and what actually makes it slow?

This app does the same job six different ways: decode a camera JPEG, resize it
to 800×600 (bilinear), encode it back to JPEG (q85), and save it to the gallery.
Then it shows the time for every stage, plus peak memory.

Built for the talk **"Rush Flutter to Native Speed — with Rust"** at
Google I/O Extended 2026, Bangkok.

> 📦 **Just want to try it?** Download the APK from the
> [Releases page](../../releases) and install it on any Android phone.

## Results (release mode, real device, average of ~10 runs)

| Implementation | Total | Decode | Process | Encode | Save | Peak RSS |
|---|---|---|---|---|---|---|
| Dart (blocking, UI thread) | 2280 ms | 996 | 1141 | 99 | 42 | +54 MB |
| Pure Dart (isolate) | 4609 ms | 1214 | 2830 | 534 | 25 | +127 MB |
| MethodChannel (Kotlin) | **132 ms** | 78 | 7 | 4 | 19 | +58 MB |
| Rust FFI (pixer) | 205 ms | 90 | 67 | 5 | 36 | +4 MB |
| Rust FFI (optimized) | **142 ms** | 86 | 13 | 4 | 26 | +45 MB |
| Native (file path, no copy) | 143 ms | 96 | 9 | 5 | 29 | +43 MB |

What the numbers mean:

- **Pure Dart is 35× slower than Kotlin** — not because Dart is not native
  (it compiles to machine code), but because the native codec (libjpeg-turbo)
  uses hand-written SIMD and Dart's `image` package does not.
- **The bridge is not the problem.** MethodChannel's copy cost is only a few
  milliseconds for a one-shot call. Kotlin even beats the naive Rust path.
- **Swap two Rust crates and the gap closes.** The optimized Rust path
  (zune-jpeg + fast_image_resize + jpeg-encoder) went from 205 ms to 142 ms —
  within 10 ms of Kotlin. The rest is libjpeg-turbo's assembly in decode.
- **Isolates fix jank, not speed.** The isolate version was even slower than
  the blocking one on this device (likely efficiency-core scheduling + data copy).

## What is inside

- **Benchmark screen** — the six cards above. Tap the 🚀 rocket (top right) to
  unlock more implementations: it starts in "slow mode" (Dart only), one tap =
  Turbo (native contenders), two taps = Super Turbo (optimized Rust).
  Long-press the rocket to export results as CSV.
- **Bridge benchmarks screen** (⇄ icon) — isolates the bridge itself:
  a slider benchmark (per-call cost) and payload scaling 1→50 MB
  (MethodChannel copies grow linearly, FFI stays flat).
- **Live editor** — brightness / pixelate / glitch effects with a
  Channel ↔ FFI transport toggle and SD/HD/Full resolution. At full
  resolution (30 MB per frame) the channel path crawls; FFI stays smooth.
  Same pixel code on both paths (C for FFI, Kotlin for channel).
- **Rust crate** (`rust/`) — connected with
  [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge);
  Gradle builds it automatically through cargokit.

## Run it yourself

Requirements:

- Flutter (any recent stable)
- Rust via [rustup](https://rustup.rs), plus the Android targets:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
```

- Android SDK + NDK (normal Flutter Android setup)

Then:

```bash
flutter pub get
flutter run --release
```

**Important: benchmark in release mode only.** Debug numbers are meaningless —
the app shows a red warning banner if you try.

Android only for now. The iOS folder exists but the native paths
(Kotlin channel handler, C live-effects library) are not wired for iOS yet.

## License

MIT — see [LICENSE](LICENSE).
