//! Images QML shows from bytes: validated by decoding them with the core's
//! image decoder (raster formats and SVG, rasterized), bounded, and
//! re-encoded as PNG data URLs, so QML never sniffs a media type or renders
//! active SVG content.

use base64::Engine;
use image::{ImageBuffer, Rgba, imageops::FilterType};

/// Decodes `bytes` and returns a PNG data URL at most `max_side` pixels on
/// its longer side; None when the bytes are not a supported image.
pub fn png_data_url(bytes: Vec<u8>, max_side: u32) -> Option<String> {
    // Decodes outside a session share one cancellation slot: a second decode
    // cancels the first, so they run one at a time.
    static DECODING: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let result = {
        let _turn = DECODING.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        gitlama_core::api::image_decode_pair(None, Some(bytes))
    };
    if result.failure.is_some() || result.decode_failure.is_some() {
        return None;
    }
    let decoded = result.new?;
    let buffer: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::from_raw(decoded.width, decoded.height, decoded.rgba)?;
    let longer = decoded.width.max(decoded.height).max(1);
    let image = if longer > max_side {
        let scale = f64::from(max_side) / f64::from(longer);
        let width = ((f64::from(decoded.width) * scale).round() as u32).max(1);
        let height = ((f64::from(decoded.height) * scale).round() as u32).max(1);
        image::imageops::resize(&buffer, width, height, FilterType::Triangle)
    } else {
        buffer
    };
    let mut png = Vec::new();
    image::DynamicImage::ImageRgba8(image)
        .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
        .ok()?;
    Some(format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(png)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_png_becomes_a_bounded_data_url() {
        let image = ImageBuffer::from_pixel(256, 128, Rgba([10u8, 20, 30, 255]));
        let mut png = Vec::new();
        image::DynamicImage::ImageRgba8(image)
            .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();
        let url = png_data_url(png, 64).unwrap();
        assert!(url.starts_with("data:image/png;base64,"));
    }

    #[test]
    fn text_is_not_an_image() {
        assert!(png_data_url(b"hello".to_vec(), 64).is_none());
    }
}

/// A decoded image as a PNG data URL, at full size.
pub fn decoded_data_url(decoded: gitlama_contract::image_decoder::NativeDecodedImage) -> Option<String> {
    let buffer: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::from_raw(decoded.width, decoded.height, decoded.rgba)?;
    let mut png = Vec::new();
    image::DynamicImage::ImageRgba8(buffer)
        .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
        .ok()?;
    Some(format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(png)))
}

/// An image diff as the presentation shows it: {failed, decodeFailure,
/// old: {url, width, height, bytes} | null, new: ...}.
pub fn image_diff_value(result: Option<gitlama_contract::dto::NativeImageDiffResult>) -> serde_json::Value {
    use gitlama_contract::image_decoder::NativeImageDecodeFailureKind as Failure;
    let Some(result) = result.filter(|result| result.failure.is_none()) else {
        return serde_json::json!({"failed": true});
    };
    let side = |image: Option<gitlama_contract::image_decoder::NativeDecodedImage>| match image {
        Some(image) => {
            let (width, height, bytes) = (image.width, image.height, image.encoded_bytes);
            match decoded_data_url(image) {
                Some(url) => serde_json::json!({"url": url, "width": width, "height": height, "bytes": bytes}),
                None => serde_json::json!({"failed": true, "width": width, "height": height, "bytes": bytes}),
            }
        }
        None => serde_json::Value::Null,
    };
    let decode_failure = result.decode_failure.map(|failure| match failure {
        Failure::Unsupported => "diffImageDecodeUnsupported",
        Failure::Malformed => "diffImageDecodeMalformed",
        Failure::TooLarge => "diffImageDecodeTooLarge",
        Failure::Busy | Failure::TimedOut | Failure::Canceled => "diffImageDecodeTimedOut",
    });
    serde_json::json!({"failed": false, "decodeFailure": decode_failure, "old": side(result.old), "new": side(result.new)})
}
