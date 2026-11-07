//! The bounded decoding worker. Desktop builds only; headless builds report images as unsupported.

use super::{DecodeResult, NativeDecodedImage, NativeImageDecodeFailureKind};
use image::{ImageFormat, ImageReader, Limits};
use std::collections::HashMap;
use std::io::Cursor;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

pub const MAX_IMAGE_ENCODED_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_IMAGE_DIMENSION: u32 = 8_192;
pub const MAX_IMAGE_PIXELS: u64 = 16_777_216;
pub const MAX_IMAGE_DECODED_BYTES: usize = 64 * 1024 * 1024;
// SVG preprocessing must not expand repository data through references,
// fonts, filters, embedded images, entities, or resource loading.
const MAX_SVG_BYTES: usize = 1024 * 1024;
const MAX_SVG_NODES: u32 = 4_096;
const MAX_SVG_DEPTH: usize = 64;
const DECODE_TIMEOUT: Duration = Duration::from_secs(2);

struct Job {
    old: Option<Vec<u8>>,
    new: Option<Vec<u8>>,
    cancellation: Arc<AtomicBool>,
    reply: SyncSender<DecodeResult>,
}

struct Worker {
    sender: Option<SyncSender<Job>>,
    admission: Mutex<()>,
}

static WORKER: OnceLock<Worker> = OnceLock::new();
static NEXT_REQUEST: AtomicU64 = AtomicU64::new(1);
type CancellationRegistry = HashMap<(u64, u64), Arc<AtomicBool>>;
static CANCELLATIONS: OnceLock<Mutex<CancellationRegistry>> = OnceLock::new();

fn worker() -> &'static Worker {
    WORKER.get_or_init(|| {
        let (sender, receiver) = mpsc::sync_channel::<Job>(1);
        let sender = std::thread::Builder::new()
            .name("gitlama-image-decoder".to_owned())
            .spawn(move || {
                while let Ok(job) = receiver.recv() {
                    let result = decode_job(&job);
                    let _ = job.reply.try_send(result);
                }
            })
            .ok()
            .map(|_| sender);
        Worker {
            sender,
            admission: Mutex::new(()),
        }
    })
}

pub(crate) fn decode_pair(
    session_id: u64,
    old: Option<Vec<u8>>,
    new: Option<Vec<u8>>,
) -> DecodeResult {
    if [old.as_ref(), new.as_ref()]
        .into_iter()
        .flatten()
        .any(|bytes| bytes.len() > MAX_IMAGE_ENCODED_BYTES)
    {
        return failure(NativeImageDecodeFailureKind::TooLarge);
    }
    let worker = worker();
    let Ok(_admission) = worker.admission.try_lock() else {
        return failure(NativeImageDecodeFailureKind::Busy);
    };
    let Some(sender) = &worker.sender else {
        return failure(NativeImageDecodeFailureKind::Busy);
    };
    let request = NEXT_REQUEST.fetch_add(1, Ordering::Relaxed).max(1);
    let cancellation = Arc::new(AtomicBool::new(false));
    lock_cancellations().insert((session_id, request), Arc::clone(&cancellation));
    let (reply, receiver) = mpsc::sync_channel(1);
    let job = Job {
        old,
        new,
        cancellation: Arc::clone(&cancellation),
        reply,
    };
    let sent = sender.try_send(job);
    if let Err(error) = sent {
        lock_cancellations().remove(&(session_id, request));
        return failure(match error {
            TrySendError::Full(_) | TrySendError::Disconnected(_) => {
                NativeImageDecodeFailureKind::Busy
            }
        });
    }
    let deadline = Instant::now() + DECODE_TIMEOUT;
    let result = loop {
        if cancellation.load(Ordering::Acquire) {
            break failure(NativeImageDecodeFailureKind::Canceled);
        }
        let now = Instant::now();
        if now >= deadline {
            cancellation.store(true, Ordering::Release);
            break failure(NativeImageDecodeFailureKind::TimedOut);
        }
        match receiver.recv_timeout((deadline - now).min(Duration::from_millis(10))) {
            Ok(value) => break value,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                break failure(NativeImageDecodeFailureKind::Busy);
            }
        }
    };
    lock_cancellations().remove(&(session_id, request));
    result
}

pub(crate) fn cancel_session(session_id: u64) {
    for ((owner, _), cancellation) in lock_cancellations().iter() {
        if *owner == session_id {
            cancellation.store(true, Ordering::Release);
        }
    }
}

fn lock_cancellations() -> std::sync::MutexGuard<'static, CancellationRegistry> {
    CANCELLATIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn decode_job(job: &Job) -> DecodeResult {
    if job.cancellation.load(Ordering::Acquire) {
        return failure(NativeImageDecodeFailureKind::Canceled);
    }
    let old = match job.old.as_deref() {
        Some(bytes) => match decode_one(bytes, MAX_IMAGE_DECODED_BYTES, &job.cancellation) {
            Ok(value) => Some(value),
            Err(kind) => return failure(kind),
        },
        None => None,
    };
    let remaining =
        MAX_IMAGE_DECODED_BYTES.saturating_sub(old.as_ref().map_or(0, |image| image.rgba.len()));
    let new = match job.new.as_deref() {
        Some(bytes) => match decode_one(bytes, remaining, &job.cancellation) {
            Ok(value) => Some(value),
            Err(kind) => return failure(kind),
        },
        None => None,
    };
    DecodeResult {
        old,
        new,
        failure: None,
    }
}

fn decode_one(
    bytes: &[u8],
    decoded_budget: usize,
    cancellation: &AtomicBool,
) -> Result<NativeDecodedImage, NativeImageDecodeFailureKind> {
    if bytes.len() > MAX_IMAGE_ENCODED_BYTES {
        return Err(NativeImageDecodeFailureKind::TooLarge);
    }
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| NativeImageDecodeFailureKind::Malformed)?;
    let Some(format) = reader.format() else {
        return decode_svg(bytes, decoded_budget, cancellation);
    };
    if !matches!(
        format,
        ImageFormat::Png
            | ImageFormat::Jpeg
            | ImageFormat::Gif
            | ImageFormat::WebP
            | ImageFormat::Bmp
            | ImageFormat::Ico
            | ImageFormat::Tiff
            | ImageFormat::Qoi
    ) {
        return Err(NativeImageDecodeFailureKind::Unsupported);
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_DIMENSION);
    limits.max_image_height = Some(MAX_IMAGE_DIMENSION);
    limits.max_alloc = Some(decoded_budget as u64);
    reader.limits(limits);
    let (width, height) = reader.into_dimensions().map_err(classify_image_error)?;
    let pixels = u64::from(width)
        .checked_mul(u64::from(height))
        .ok_or(NativeImageDecodeFailureKind::TooLarge)?;
    let decoded = pixels
        .checked_mul(4)
        .ok_or(NativeImageDecodeFailureKind::TooLarge)?;
    if width > MAX_IMAGE_DIMENSION
        || height > MAX_IMAGE_DIMENSION
        || pixels > MAX_IMAGE_PIXELS
        || decoded > decoded_budget as u64
    {
        return Err(NativeImageDecodeFailureKind::TooLarge);
    }
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| NativeImageDecodeFailureKind::Malformed)?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_DIMENSION);
    limits.max_image_height = Some(MAX_IMAGE_DIMENSION);
    limits.max_alloc = Some(decoded_budget as u64);
    reader.limits(limits);
    let rgba = reader
        .decode()
        .map_err(classify_image_error)?
        .into_rgba8()
        .into_raw();
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    if rgba.len() != decoded as usize || rgba.len() > decoded_budget {
        return Err(NativeImageDecodeFailureKind::TooLarge);
    }
    Ok(NativeDecodedImage {
        width,
        height,
        encoded_bytes: bytes.len() as u64,
        rgba,
    })
}

fn decode_svg(
    bytes: &[u8],
    decoded_budget: usize,
    cancellation: &AtomicBool,
) -> Result<NativeDecodedImage, NativeImageDecodeFailureKind> {
    let text = std::str::from_utf8(bytes).map_err(|_| NativeImageDecodeFailureKind::Unsupported)?;
    if !text
        .trim_start_matches('\u{feff}')
        .trim_start()
        .starts_with('<')
    {
        return Err(NativeImageDecodeFailureKind::Unsupported);
    }
    if bytes.len() > MAX_SVG_BYTES {
        return Err(NativeImageDecodeFailureKind::TooLarge);
    }
    let document = roxmltree::Document::parse_with_options(
        text,
        roxmltree::ParsingOptions {
            allow_dtd: false,
            nodes_limit: MAX_SVG_NODES,
            ..Default::default()
        },
    )
    .map_err(|error| match error {
        roxmltree::Error::NodesLimitReached => NativeImageDecodeFailureKind::TooLarge,
        _ => NativeImageDecodeFailureKind::Malformed,
    })?;
    if !document
        .root_element()
        .has_tag_name(("http://www.w3.org/2000/svg", "svg"))
    {
        return Err(NativeImageDecodeFailureKind::Unsupported);
    }
    for node in document.descendants().filter(roxmltree::Node::is_element) {
        if node.ancestors().take(MAX_SVG_DEPTH + 1).count() > MAX_SVG_DEPTH {
            return Err(NativeImageDecodeFailureKind::TooLarge);
        }
        // Explicitly support geometry, paint servers, clipping, masks and
        // filters that only transform pixels already drawn. Reject active
        // documents, external resources (`feImage`, `image`), text without
        // bundled fonts, and `use`, whose references multiply the bounded
        // document, before preprocessing.
        if node.tag_name().namespace() != Some("http://www.w3.org/2000/svg")
            || !matches!(
                node.tag_name().name(),
                "svg"
                    | "g"
                    | "defs"
                    | "path"
                    | "rect"
                    | "circle"
                    | "ellipse"
                    | "line"
                    | "polyline"
                    | "polygon"
                    | "linearGradient"
                    | "radialGradient"
                    | "stop"
                    | "clipPath"
                    | "mask"
                    | "pattern"
                    | "marker"
                    | "filter"
                    | "feBlend"
                    | "feColorMatrix"
                    | "feComponentTransfer"
                    | "feFuncR"
                    | "feFuncG"
                    | "feFuncB"
                    | "feFuncA"
                    | "feComposite"
                    | "feDropShadow"
                    | "feFlood"
                    | "feGaussianBlur"
                    | "feMerge"
                    | "feMergeNode"
                    | "feMorphology"
                    | "feOffset"
                    | "title"
                    | "desc"
            )
            || node.attributes().any(|attribute| {
                attribute.name().starts_with("on")
                    || (attribute.name() == "href" && !attribute.value().starts_with('#'))
            })
        {
            return Err(NativeImageDecodeFailureKind::Unsupported);
        }
    }
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    let options = resvg::usvg::Options {
        image_href_resolver: resvg::usvg::ImageHrefResolver {
            resolve_data: Box::new(|_, _, _| None),
            resolve_string: Box::new(|_, _| None),
        },
        ..Default::default()
    };
    // Reuse the already bounded XML document. usvg's string parser enables
    // DTDs, and its data parser can decompress SVGZ without our byte budget.
    let tree = resvg::usvg::Tree::from_xmltree(&document, &options)
        .map_err(|_| NativeImageDecodeFailureKind::Malformed)?;
    // resvg fits group and filter layers to the canvas, but renders each
    // pattern tile at its own scaled size.
    bounded_patterns(tree.root(), false)?;
    let size = tree.size().to_int_size();
    let (width, height) = (size.width(), size.height());
    let pixels = u64::from(width) * u64::from(height);
    if width > MAX_IMAGE_DIMENSION
        || height > MAX_IMAGE_DIMENSION
        || pixels > MAX_IMAGE_PIXELS
        || pixels * 4 > decoded_budget as u64
    {
        return Err(NativeImageDecodeFailureKind::TooLarge);
    }
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height)
        .ok_or(NativeImageDecodeFailureKind::TooLarge)?;
    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );
    if cancellation.load(Ordering::Acquire) {
        return Err(NativeImageDecodeFailureKind::Canceled);
    }
    // tiny-skia renders premultiplied pixels; Flutter's rgba8888 upload expects
    // straight alpha, as does the existing raster decoder.
    Ok(NativeDecodedImage {
        width,
        height,
        encoded_bytes: bytes.len() as u64,
        rgba: pixmap.take_demultiplied(),
    })
}

/// Rejects pattern tiles larger than an image the decoder would accept, and
/// patterns inside patterns, masks or clips, whose tiles scale with the
/// outer use.
fn bounded_patterns(
    group: &resvg::usvg::Group,
    nested: bool,
) -> Result<(), NativeImageDecodeFailureKind> {
    for node in group.children() {
        if let resvg::usvg::Node::Path(path) = node {
            let paints = [
                path.fill().map(|fill| fill.paint()),
                path.stroke().map(|stroke| stroke.paint()),
            ];
            for paint in paints.into_iter().flatten() {
                let resvg::usvg::Paint::Pattern(pattern) = paint else {
                    continue;
                };
                if nested {
                    return Err(NativeImageDecodeFailureKind::Unsupported);
                }
                let (sx, sy) = path
                    .abs_transform()
                    .pre_concat(pattern.transform())
                    .get_scale();
                let width = f64::from(pattern.rect().width() * sx).round();
                let height = f64::from(pattern.rect().height() * sy).round();
                if !width.is_finite()
                    || !height.is_finite()
                    || width > f64::from(MAX_IMAGE_DIMENSION)
                    || height > f64::from(MAX_IMAGE_DIMENSION)
                    || width * height > MAX_IMAGE_PIXELS as f64
                {
                    return Err(NativeImageDecodeFailureKind::TooLarge);
                }
            }
        }
        if let resvg::usvg::Node::Group(child) = node {
            bounded_patterns(child, nested)?;
        }
        let mut result = Ok(());
        node.subroots(|root| {
            if result.is_ok() {
                result = bounded_patterns(root, true);
            }
        });
        result?;
    }
    Ok(())
}

fn classify_image_error(error: image::ImageError) -> NativeImageDecodeFailureKind {
    match error {
        image::ImageError::Limits(_) => NativeImageDecodeFailureKind::TooLarge,
        image::ImageError::Unsupported(_) => NativeImageDecodeFailureKind::Unsupported,
        _ => NativeImageDecodeFailureKind::Malformed,
    }
}

const fn failure(kind: NativeImageDecodeFailureKind) -> DecodeResult {
    DecodeResult {
        old: None,
        new: None,
        failure: Some(kind),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, ImageEncoder, Rgba};

    fn png(width: u32, height: u32) -> Vec<u8> {
        let pixels = ImageBuffer::from_pixel(width, height, Rgba([1_u8, 2, 3, 255]));
        let mut bytes = Vec::new();
        image::codecs::png::PngEncoder::new(&mut bytes)
            .write_image(
                pixels.as_raw(),
                width,
                height,
                image::ExtendedColorType::Rgba8,
            )
            .unwrap();
        bytes
    }

    fn decode_svg_fixture(
        text: &str,
        budget: usize,
    ) -> Result<NativeDecodedImage, NativeImageDecodeFailureKind> {
        decode_one(text.as_bytes(), budget, &AtomicBool::new(false))
    }

    #[test]
    fn passive_svg_decodes_lucide_geometry_and_straight_alpha() {
        let decoded = decode_svg_fixture(
            include_str!("../../test-fixtures/images/wallpaper.svg"),
            MAX_IMAGE_DECODED_BYTES,
        )
        .unwrap();
        assert_eq!((decoded.width, decoded.height), (24, 24));
        assert_eq!(decoded.rgba.len(), 24 * 24 * 4);
        assert_eq!(
            decoded.encoded_bytes,
            include_str!("../../test-fixtures/images/wallpaper.svg").len() as u64
        );
        assert!(decoded.rgba.chunks_exact(4).any(|pixel| pixel[3] > 0));
        let transparent = decode_svg_fixture(
            r#"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="red" opacity="0.5"/></svg>"#,
            16,
        ).unwrap();
        assert_eq!(transparent.rgba, [255, 0, 0, 128].repeat(4));
    }

    #[test]
    fn svg_gradients_and_clipping_produce_visible_and_transparent_pixels() {
        let image = decode_svg_fixture(
            r##"<svg xmlns="http://www.w3.org/2000/svg" width="4" height="2">
            <defs><linearGradient id="paint"><stop stop-color="red"/>
            <stop offset="1" stop-color="blue"/></linearGradient>
            <clipPath id="clip"><rect width="2" height="2"/></clipPath></defs>
            <rect width="4" height="2" fill="url(#paint)" clip-path="url(#clip)"/>
            </svg>"##,
            32,
        )
        .unwrap();
        assert_eq!((image.width, image.height), (4, 2));
        assert_eq!(image.rgba[3], 255);
        assert_ne!(image.rgba[..4], image.rgba[4..8]);
        assert_eq!(image.rgba[11], 0);
        assert_eq!(image.rgba[15], 0);
    }

    #[test]
    fn svg_filters_patterns_and_masks_render() {
        let image = decode_svg_fixture(
            r##"<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">
            <defs>
            <filter id="soft" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="1"/></filter>
            <pattern id="grid" width="2" height="2" patternUnits="userSpaceOnUse"><rect width="1" height="1" fill="red"/></pattern>
            <mask id="half"><rect width="4" height="8" fill="white"/></mask>
            </defs>
            <rect width="8" height="8" fill="url(#grid)" mask="url(#half)"/>
            <g filter="url(#soft)"><circle cx="6" cy="6" r="1" fill="blue"/></g>
            </svg>"##,
            MAX_IMAGE_DECODED_BYTES,
        )
        .unwrap();
        let pixel = |x: usize, y: usize| &image.rgba[(y * 8 + x) * 4..(y * 8 + x) * 4 + 4];
        // The pattern repeats inside the mask and is masked out beside it.
        assert_eq!(pixel(0, 0), [255, 0, 0, 255]);
        assert_eq!(pixel(1, 1)[3], 0);
        assert_eq!(pixel(2, 2), [255, 0, 0, 255]);
        assert_eq!(pixel(4, 0)[3], 0);
        // The blur spreads the circle beyond its own edge.
        assert!(pixel(6, 4)[3] > 0);
    }

    #[test]
    fn svg_pattern_tiles_are_bounded() {
        let pattern = |tile: &str, use_site: &str| {
            format!(
                r##"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><defs>{tile}</defs>{use_site}</svg>"##
            )
        };
        let huge = pattern(
            r#"<pattern id="p" width="1" height="1" patternUnits="userSpaceOnUse" patternTransform="scale(100000)"><rect width="1" height="1"/></pattern>"#,
            r#"<rect width="2" height="2" fill="url(#p)"/>"#,
        );
        assert_eq!(
            decode_svg_fixture(&huge, MAX_IMAGE_DECODED_BYTES),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
        let nested = pattern(
            r#"<pattern id="inner" width="1" height="1" patternUnits="userSpaceOnUse"><rect width="1" height="1"/></pattern><pattern id="outer" width="2" height="2" patternUnits="userSpaceOnUse"><rect width="2" height="2" fill="url(#inner)"/></pattern>"#,
            r#"<rect width="2" height="2" fill="url(#outer)"/>"#,
        );
        assert_eq!(
            decode_svg_fixture(&nested, MAX_IMAGE_DECODED_BYTES),
            Err(NativeImageDecodeFailureKind::Unsupported)
        );
    }

    #[test]
    fn svg_limits_cover_dimensions_pair_budget_nodes_depth_and_cancellation() {
        let image = |width| {
            format!(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="2"><rect width="2" height="2"/></svg>"#
            )
        };
        assert_eq!(
            decode_svg_fixture(&image(8_193), MAX_IMAGE_DECODED_BYTES),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
        assert_eq!(
            decode_svg_fixture(&image(2), 15),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
        let many_nodes = format!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">{}</svg>"#,
            "<rect/>".repeat(MAX_SVG_NODES as usize)
        );
        assert_eq!(
            decode_svg_fixture(&many_nodes, 16),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
        let deep = format!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">{}{}{}</svg>"#,
            "<g>".repeat(MAX_SVG_DEPTH),
            "<rect/>",
            "</g>".repeat(MAX_SVG_DEPTH)
        );
        assert_eq!(
            decode_svg_fixture(&deep, 16),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
        assert_eq!(
            decode_one(image(2).as_bytes(), 16, &AtomicBool::new(true)),
            Err(NativeImageDecodeFailureKind::Canceled)
        );
        let large = format!("{}{}", image(2), " ".repeat(MAX_SVG_BYTES));
        assert_eq!(
            decode_svg_fixture(&large, 16),
            Err(NativeImageDecodeFailureKind::TooLarge)
        );
    }

    #[test]
    fn svg_rejects_document_entities_and_resource_or_expansion_features() {
        for body in [
            "<image href='file:///private/image.png'/>",
            "<image href='https://example.invalid/image.png'/>",
            "<image href='data:image/png;base64,AA=='/>",
            "<script>throw new Error('private')</script>",
            "<foreignObject/>",
            "<feImage href='https://example.invalid/image.png'/>",
            "<filter><feImage href='#shape'/></filter>",
            "<filter><feTurbulence baseFrequency='0.1'/></filter>",
            "<use href='#shape'/>",
            "<text>unsupported font content</text>",
            "<rect onload='private()'/>",
        ] {
            let svg = format!(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">{body}</svg>"#
            );
            assert_eq!(
                decode_svg_fixture(&svg, 16),
                Err(NativeImageDecodeFailureKind::Unsupported)
            );
        }
        let entity = r#"<!DOCTYPE svg [<!ENTITY private "content">]><svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><title>&private;</title></svg>"#;
        assert_eq!(
            decode_svg_fixture(entity, 16),
            Err(NativeImageDecodeFailureKind::Malformed)
        );
    }

    fn encoded(format: ImageFormat) -> Vec<u8> {
        let pixels = ImageBuffer::from_pixel(2, 3, Rgba([1_u8, 2, 3, 255]));
        let mut bytes = Cursor::new(Vec::new());
        pixels.write_to(&mut bytes, format).unwrap();
        bytes.into_inner()
    }

    #[test]
    fn bmp_ico_tiff_and_qoi_decode_to_rgba() {
        for format in [
            ImageFormat::Bmp,
            ImageFormat::Ico,
            ImageFormat::Tiff,
            ImageFormat::Qoi,
        ] {
            let decoded = decode_one(
                &encoded(format),
                MAX_IMAGE_DECODED_BYTES,
                &AtomicBool::new(false),
            )
            .unwrap();
            assert_eq!((decoded.width, decoded.height), (2, 3), "{format:?}");
            assert_eq!(decoded.rgba, [1, 2, 3, 255].repeat(6), "{format:?}");
        }
    }

    #[test]
    fn decoder_returns_exact_bounded_rgba_and_rejects_unsupported_content() {
        let encoded = png(2, 3);
        let encoded_bytes = encoded.len() as u64;
        let decoded = decode_pair(91_001, Some(encoded), None);
        let old = decoded.old.unwrap();
        assert_eq!((old.width, old.height), (2, 3));
        assert_eq!(old.encoded_bytes, encoded_bytes);
        assert_eq!(old.rgba.len(), 24);
        assert_eq!(decoded.failure, None);

        let svg = decode_pair(91_002, None, Some(b"<svg width='1'/>".to_vec()));
        assert_eq!(svg.failure, Some(NativeImageDecodeFailureKind::Unsupported));
        let malformed = decode_pair(91_003, Some(b"not an image".to_vec()), None);
        assert_eq!(
            malformed.failure,
            Some(NativeImageDecodeFailureKind::Unsupported)
        );

        let oversized_dimensions = decode_pair(91_004, Some(png(8_193, 1)), None);
        assert_eq!(
            oversized_dimensions.failure,
            Some(NativeImageDecodeFailureKind::TooLarge)
        );
    }
}
