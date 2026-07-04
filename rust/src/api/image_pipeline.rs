use std::time::Instant;

use anyhow::{anyhow, Result};
use fast_image_resize::images::Image;
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use jpeg_encoder::{ColorType, Encoder};
use zune_jpeg::zune_core::colorspace::ColorSpace;
use zune_jpeg::zune_core::options::DecoderOptions;
use zune_jpeg::JpegDecoder;

pub struct ProcessResult {
    pub jpeg: Vec<u8>,
    pub decode_ms: u32,
    pub process_ms: u32,
    pub encode_ms: u32,
}

pub fn process_image(jpeg: Vec<u8>, w: u32, h: u32, quality: u8) -> Result<ProcessResult> {
    let t0 = Instant::now();
    let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::RGB);
    let mut decoder = JpegDecoder::new_with_options(&jpeg, options);
    let pixels = decoder.decode().map_err(|e| anyhow!("decode: {e:?}"))?;
    let info = decoder
        .info()
        .ok_or_else(|| anyhow!("no jpeg info after decode"))?;
    let (src_w, src_h) = (info.width as u32, info.height as u32);
    let decode_ms = t0.elapsed().as_millis() as u32;

    let t1 = Instant::now();
    let src = Image::from_vec_u8(src_w, src_h, pixels, PixelType::U8x3)?;
    let mut dst = Image::new(w, h, PixelType::U8x3);
    let mut resizer = Resizer::new();
    // Bilinear: filter parity with the Kotlin path and pixer (Triangle).
    resizer.resize(
        &src,
        &mut dst,
        &ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear)),
    )?;
    let process_ms = t1.elapsed().as_millis() as u32;

    let t2 = Instant::now();
    let mut out = Vec::new();
    let encoder = Encoder::new(&mut out, quality);
    encoder.encode(dst.buffer(), w as u16, h as u16, ColorType::Rgb)?;
    let encode_ms = t2.elapsed().as_millis() as u32;

    Ok(ProcessResult {
        jpeg: out,
        decode_ms,
        process_ms,
        encode_ms,
    })
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities (panic hook, logging) — from the frb template.
    flutter_rust_bridge::setup_default_user_utils();
}
