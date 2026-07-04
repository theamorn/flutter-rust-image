/// FFI binding for the Live Editor's C effects library.
///
/// Pixels are written into native memory ONCE per resolution; each apply is a
/// single synchronous C call on those shared buffers — zero bridge copies.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _ApplyEffectNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Uint8> src,
      ffi.Pointer<ffi.Uint8> dst,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 effect,
      ffi.Int32 value,
    );
typedef _ApplyEffectDart =
    void Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      int,
      int,
    );

class LiveEffectsFfi {
  LiveEffectsFfi()
    : _apply = ffi.DynamicLibrary.open(
        'liblive_effects.so',
      ).lookupFunction<_ApplyEffectNative, _ApplyEffectDart>('apply_effect');

  final _ApplyEffectDart _apply;
  ffi.Pointer<ffi.Uint8> _src = ffi.nullptr;
  ffi.Pointer<ffi.Uint8> _dst = ffi.nullptr;
  int _size = 0;

  /// Copies [rgba] into native memory once. Until the next [setSource] or
  /// [dispose], applies run entirely on the native side.
  void setSource(Uint8List rgba) {
    _free();
    _size = rgba.length;
    _src = malloc.allocate<ffi.Uint8>(_size);
    _dst = malloc.allocate<ffi.Uint8>(_size);
    _src.asTypedList(_size).setAll(0, rgba);
  }

  /// Runs the effect in C and returns a VIEW of the destination buffer — no
  /// copy. The view is invalidated by the next [setSource] or [dispose].
  Uint8List apply(int width, int height, int effect, int value) {
    if (_size != width * height * 4) {
      throw StateError('setSource was not called for this resolution');
    }
    _apply(_src, _dst, width, height, effect, value);
    return _dst.asTypedList(_size);
  }

  void _free() {
    if (_src != ffi.nullptr) malloc.free(_src);
    if (_dst != ffi.nullptr) malloc.free(_dst);
    _src = ffi.nullptr;
    _dst = ffi.nullptr;
    _size = 0;
  }

  void dispose() => _free();
}
