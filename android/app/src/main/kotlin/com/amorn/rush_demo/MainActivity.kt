package com.amorn.rush_demo

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rush_demo/native")
            .setMethodCallHandler { call, result ->
                if (call.method == "resizeCompressSave") {
                    val bytes = call.argument<ByteArray>("bytes")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val quality = call.argument<Int>("quality")!!

                    // Run on a background thread — FFI is synchronous; long calls block
                    // whichever thread they're on. Never block the platform/UI thread.
                    Thread {
                        try {
                            val decodeStart = System.nanoTime()
                            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            val decodeMs = (System.nanoTime() - decodeStart) / 1_000_000

                            val processStart = System.nanoTime()
                            val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
                            bitmap.recycle()
                            val processMs = (System.nanoTime() - processStart) / 1_000_000

                            val encodeStart = System.nanoTime()
                            val out = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
                            val jpegBytes = out.toByteArray()
                            scaled.recycle()
                            val encodeMs = (System.nanoTime() - encodeStart) / 1_000_000

                            val saveStart = System.nanoTime()
                            saveToGallery(jpegBytes)
                            val saveMs = (System.nanoTime() - saveStart) / 1_000_000

                            result.success(
                                mapOf(
                                    "decodeMs" to decodeMs.toInt(),
                                    "processMs" to processMs.toInt(),
                                    "encodeMs" to encodeMs.toInt(),
                                    "saveMs" to saveMs.toInt(),
                                    "outputBytes" to jpegBytes.size,
                                )
                            )
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.message, null)
                        }
                    }.start()
                } else if (call.method == "readProcessSave") {
                    // Bridge receives only a file path string (~O(1) bytes, no image copy).
                    // Kotlin reads, decodes, resizes, encodes, and saves entirely on the
                    // native side. Represents "pure native" speed with zero byte serialization.
                    val path = call.argument<String>("path")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val quality = call.argument<Int>("quality")!!

                    Thread {
                        try {
                            val decodeStart = System.nanoTime()
                            val bitmap = BitmapFactory.decodeFile(path)
                            val decodeMs = (System.nanoTime() - decodeStart) / 1_000_000

                            val processStart = System.nanoTime()
                            val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
                            bitmap.recycle()
                            val processMs = (System.nanoTime() - processStart) / 1_000_000

                            val encodeStart = System.nanoTime()
                            val out = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
                            val jpegBytes = out.toByteArray()
                            scaled.recycle()
                            val encodeMs = (System.nanoTime() - encodeStart) / 1_000_000

                            val saveStart = System.nanoTime()
                            saveToGallery(jpegBytes)
                            val saveMs = (System.nanoTime() - saveStart) / 1_000_000

                            result.success(
                                mapOf(
                                    "decodeMs" to decodeMs.toInt(),
                                    "processMs" to processMs.toInt(),
                                    "encodeMs" to encodeMs.toInt(),
                                    "saveMs" to saveMs.toInt(),
                                    "outputBytes" to jpegBytes.size,
                                )
                            )
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.message, null)
                        }
                    }.start()
                } else if (call.method == "adjustBrightness") {
                    // Chatty-call demo: the RGBA preview crosses the bridge in
                    // BOTH directions on every call. Compute itself is cheap.
                    val rgba = call.argument<ByteArray>("rgba")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val value = call.argument<Int>("value")!!

                    Thread {
                        try {
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))

                            val adjusted = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val v = value.toFloat()
                            val paint = Paint().apply {
                                colorFilter = ColorMatrixColorFilter(
                                    ColorMatrix(
                                        floatArrayOf(
                                            1f, 0f, 0f, 0f, v,
                                            0f, 1f, 0f, 0f, v,
                                            0f, 0f, 1f, 0f, v,
                                            0f, 0f, 0f, 1f, 0f,
                                        )
                                    )
                                )
                            }
                            Canvas(adjusted).drawBitmap(bitmap, 0f, 0f, paint)
                            bitmap.recycle()

                            val out = ByteBuffer.allocate(adjusted.byteCount)
                            adjusted.copyPixelsToBuffer(out)
                            adjusted.recycle()
                            result.success(out.array())
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.message, null)
                        }
                    }.start()
                } else if (call.method == "fillBuffer") {
                    // Payload demo: the array already cost one copy inbound;
                    // returning it costs another. Fill matches the FFI memset.
                    val bytes = call.arguments as ByteArray
                    Thread {
                        try {
                            java.util.Arrays.fill(bytes, 0x42.toByte())
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.message, null)
                        }
                    }.start()
                } else if (call.method == "applyEffect") {
                    // Live Editor channel path: the full RGBA frame crosses the
                    // bridge in BOTH directions on every call. Same hand-written
                    // pixel loops as the C library — equal compute, only the
                    // transport differs.
                    val rgba = call.argument<ByteArray>("rgba")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val effect = call.argument<Int>("effect")!!
                    val value = call.argument<Int>("value")!!

                    Thread {
                        try {
                            val out = ByteArray(rgba.size)
                            applyEffectPixels(rgba, out, width, height, effect, value)
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.message, null)
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun saveToGallery(bytes: ByteArray) {
        val filename = "rush_native_${System.currentTimeMillis()}.jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/rush_demo")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
        contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        }
    }

    // Mirrors live_effects.c exactly. effect: 0=brightness, 1=pixelate, 2=glitch.
    private fun applyEffectPixels(
        src: ByteArray, dst: ByteArray,
        width: Int, height: Int, effect: Int, value: Int,
    ) {
        when (effect) {
            0 -> { // brightness: value 0..100 -> delta -50..+50
                val d = value - 50
                var i = 0
                while (i < src.size) {
                    dst[i] = ((src[i].toInt() and 0xFF) + d).coerceIn(0, 255).toByte()
                    dst[i + 1] = ((src[i + 1].toInt() and 0xFF) + d).coerceIn(0, 255).toByte()
                    dst[i + 2] = ((src[i + 2].toInt() and 0xFF) + d).coerceIn(0, 255).toByte()
                    dst[i + 3] = src[i + 3]
                    i += 4
                }
            }
            1 -> { // pixelate: block size 1..64
                val block = 1 + (value * 63) / 100
                for (y in 0 until height) {
                    val by = (y / block) * block
                    for (x in 0 until width) {
                        val bx = (x / block) * block
                        val s = (by * width + bx) * 4
                        val o = (y * width + x) * 4
                        dst[o] = src[s]
                        dst[o + 1] = src[s + 1]
                        dst[o + 2] = src[s + 2]
                        dst[o + 3] = src[s + 3]
                    }
                }
            }
            else -> { // glitch: RGB shift 0..30px + line displacement every 16th row
                val shift = (value * 30) / 100
                for (y in 0 until height) {
                    var rowOff = 0
                    if (shift > 0 && y % 16 == 0) {
                        rowOff = ((y * 31 + value) % (2 * shift + 1)) - shift
                    }
                    val rowBase = y * width * 4
                    for (x in 0 until width) {
                        var xs = x + rowOff
                        if (xs < 0) xs = 0
                        if (xs >= width) xs = width - 1
                        var xr = xs + shift
                        if (xr >= width) xr = width - 1
                        var xb = xs - shift
                        if (xb < 0) xb = 0
                        val o = (y * width + x) * 4
                        dst[o] = src[rowBase + xr * 4]
                        dst[o + 1] = src[rowBase + xs * 4 + 1]
                        dst[o + 2] = src[rowBase + xb * 4 + 2]
                        dst[o + 3] = src[rowBase + xs * 4 + 3]
                    }
                }
            }
        }
    }
}
