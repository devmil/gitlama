import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../app/byte_size.dart';
import '../l10n/l10n.dart';
import '../models/diff.dart';
import '../models/repository_state.dart';

/// The image change row in a loaded diff, if the diff compares images.
DiffDisplayRow? imageDiffRow(Iterable<DiffDisplayRow> rows) {
  for (final row in rows) {
    if (row.kind == DiffRowKind.image) return row;
  }
  return null;
}

/// Loads one image change and shows it inline in a diff pane.
///
/// A null result or repository failure shows a load failure; stale requests
/// are replaced when the pane selects another change.
class ImageDiffView extends StatefulWidget {
  const ImageDiffView({required this.load, super.key});

  final Future<ImageDiffContent?> Function() load;

  @override
  State<ImageDiffView> createState() => _ImageDiffViewState();
}

class _ImageDiffViewState extends State<ImageDiffView> {
  ImageDiffContent? _content;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final content = await widget.load();
      if (mounted) {
        setState(() {
          _content = content;
          _failed = content == null;
        });
      }
    } on RepositorySessionException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    if (_failed) {
      return MeridianEmptyState(
        compact: true,
        icon: 'circle-alert',
        title: context.l10n.diffImageLoadFailed,
      );
    }
    if (content == null) {
      return Column(
        children: [
          const MeridianProgressBar(),
          Expanded(
            child: MeridianEmptyState(
              compact: true,
              title: context.l10n.diffImagePreparing,
            ),
          ),
        ],
      );
    }
    return ImageDiffComparison(content: content);
  }
}

enum _ImageDiffMode { sideBySide, swipe, onionSkin }

/// Side-by-side, swipe and onion-skin comparison of decoded image sides.
class ImageDiffComparison extends StatefulWidget {
  const ImageDiffComparison({required this.content, super.key});

  final ImageDiffContent content;

  @override
  State<ImageDiffComparison> createState() => _ImageDiffComparisonState();
}

class _ImageDiffComparisonState extends State<ImageDiffComparison> {
  _ImageDiffMode _mode = _ImageDiffMode.sideBySide;
  double _amount = 0.5;

  @override
  Widget build(BuildContext context) {
    // Without decoded sides there is nothing to compare; say why once instead
    // of calling both sides empty.
    if (widget.content.failure case final failure?) {
      return MeridianEmptyState(
        compact: true,
        icon: 'circle-alert',
        title: context.l10n.diffImageDecodeFailed,
        message: switch (failure) {
          ImageDecodeFailure.unsupported =>
            context.l10n.diffImageDecodeUnsupported,
          ImageDecodeFailure.malformed => context.l10n.diffImageDecodeMalformed,
          ImageDecodeFailure.tooLarge => context.l10n.diffImageDecodeTooLarge,
          ImageDecodeFailure.busy ||
          ImageDecodeFailure.timedOut ||
          ImageDecodeFailure.canceled => context.l10n.diffImageDecodeTimedOut,
        },
      );
    }
    return _comparisonWithControls(context);
  }

  Widget _comparisonWithControls(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(MeridianSpace.space3),
        child: Wrap(
          spacing: MeridianSpace.space4,
          runSpacing: MeridianSpace.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MeridianSegmented<_ImageDiffMode>(
              label: context.l10n.diffImageComparison,
              segments: [
                for (final value in _ImageDiffMode.values)
                  MeridianSegment(
                    value: value,
                    label: switch (value) {
                      _ImageDiffMode.sideBySide =>
                        context.l10n.diffImageSideBySide,
                      _ImageDiffMode.swipe => context.l10n.diffImageSwipe,
                      _ImageDiffMode.onionSkin =>
                        context.l10n.diffImageOnionSkin,
                    },
                  ),
              ],
              value: _mode,
              onChanged: (value) => setState(() => _mode = value),
              size: MeridianControlSize.small,
            ),
            // Stacked sides share one area, so their sizes are listed here.
            if (_mode != _ImageDiffMode.sideBySide)
              for (final (label, image) in [
                (context.l10n.diffOldImage, widget.content.old),
                (context.l10n.diffNewImage, widget.content.newImage),
              ])
                if (image != null)
                  Text(
                    context.l10n.diffImageSideDetails(
                      label,
                      _imageDetails(context, image),
                    ),
                    style: context.text.caption.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
          ],
        ),
      ),
      if (_mode != _ImageDiffMode.sideBySide)
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: MeridianSpace.space3,
          ),
          child: Row(
            children: [
              Text(
                _mode == _ImageDiffMode.swipe
                    ? context.l10n.diffImageDivider
                    : context.l10n.diffImageBlend,
              ),
              Expanded(
                child: MeridianSlider(
                  key: const Key('image-diff-amount'),
                  label: _mode == _ImageDiffMode.swipe
                      ? context.l10n.diffImageDivider
                      : context.l10n.diffImageBlend,
                  value: _amount,
                  onChanged: (value) => setState(() => _amount = value),
                ),
              ),
            ],
          ),
        ),
      Expanded(child: _comparison(context)),
    ],
  );

  Widget _comparison(BuildContext context) => switch (_mode) {
    _ImageDiffMode.sideBySide => Row(
      children: [
        Expanded(
          child: _DiffImageSide(
            label: context.l10n.diffOldImage,
            image: widget.content.old,
          ),
        ),
        const MeridianHairline(axis: Axis.vertical),
        Expanded(
          child: _DiffImageSide(
            label: context.l10n.diffNewImage,
            image: widget.content.newImage,
          ),
        ),
      ],
    ),
    _ImageDiffMode.swipe => LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          _DiffImageSide(
            label: context.l10n.diffOldImage,
            image: widget.content.old,
            stacked: true,
          ),
          ClipRect(
            clipper: _HorizontalImageClipper(_amount),
            child: _DiffImageSide(
              label: context.l10n.diffNewImage,
              image: widget.content.newImage,
              stacked: true,
            ),
          ),
        ],
      ),
    ),
    _ImageDiffMode.onionSkin => Stack(
      fit: StackFit.expand,
      children: [
        _DiffImageSide(
          label: context.l10n.diffOldImage,
          image: widget.content.old,
          stacked: true,
        ),
        Opacity(
          opacity: _amount,
          child: _DiffImageSide(
            label: context.l10n.diffNewImage,
            image: widget.content.newImage,
            stacked: true,
          ),
        ),
      ],
    ),
  };
}

class _HorizontalImageClipper extends CustomClipper<Rect> {
  const _HorizontalImageClipper(this.amount);

  final double amount;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * amount, size.height);

  @override
  bool shouldReclip(_HorizontalImageClipper oldClipper) =>
      oldClipper.amount != amount;
}

/// Pixel dimensions and, when known, the stored file size of [image]:
/// "640 × 480 px · 47 KB".
String _imageDetails(BuildContext context, DecodedImageContent image) {
  final l10n = context.l10n;
  final dimensions = l10n.diffImageDimensions(image.width, image.height);
  final bytes = image.encodedBytes;
  return bytes == null
      ? dimensions
      : l10n.diffImageDetails(dimensions, formatByteSize(l10n, bytes));
}

class _DiffImageSide extends StatefulWidget {
  const _DiffImageSide({
    required this.label,
    required this.image,
    this.stacked = false,
  });

  final String label;
  final DecodedImageContent? image;

  /// Drawn over the other side, whose label would overlap this one; the
  /// comparison controls name both sides instead.
  final bool stacked;

  @override
  State<_DiffImageSide> createState() => _DiffImageSideState();
}

class _DiffImageSideState extends State<_DiffImageSide> {
  ui.Image? _image;
  bool _failed = false;
  int _uploadToken = 0;

  @override
  void initState() {
    super.initState();
    _upload();
  }

  @override
  void didUpdateWidget(covariant _DiffImageSide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) _upload();
  }

  Future<void> _upload() async {
    final token = ++_uploadToken;
    _image?.dispose();
    _image = null;
    _failed = false;
    final image = widget.image;
    if (image == null) return;
    final expected = image.width * image.height * 4;
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.rgba.length != expected) {
      _failed = true;
      return;
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        Uint8List.fromList(image.rgba),
      );
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: image.width,
        height: image.height,
        rowBytes: image.width * 4,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      if (!mounted ||
          token != _uploadToken ||
          !identical(image, widget.image)) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted && token == _uploadToken) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _uploadToken += 1;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    image: true,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MeridianSpace.space4),
          child: Text(
            switch (widget.image) {
              _ when widget.stacked => '',
              final image? => context.l10n.diffImageSideDetails(
                widget.label,
                _imageDetails(context, image),
              ),
              null => widget.label,
            },
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
        ),
        Expanded(
          child: widget.image == null
              ? MeridianEmptyState(
                  compact: true,
                  title: context.l10n.diffImageMissing,
                )
              : _failed
              ? MeridianEmptyState(
                  compact: true,
                  icon: 'circle-alert',
                  title: context.l10n.diffImageDecodeFailed,
                )
              : _image == null
              ? MeridianEmptyState(
                  compact: true,
                  title: context.l10n.diffImagePreparing,
                )
              : CustomPaint(
                  painter: _ImageCheckerboardPainter(
                    pane: context.colors.pane,
                    alternate: context.colors.paneAlt,
                  ),
                  child: SizedBox.expand(
                    child: RawImage(
                      image: _image,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _ImageCheckerboardPainter extends CustomPainter {
  const _ImageCheckerboardPainter({
    required this.pane,
    required this.alternate,
  });

  final Color pane;
  final Color alternate;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pane);
    final paint = Paint()..color = alternate;
    for (var y = 0; y < size.height; y += 8) {
      for (var x = ((y ~/ 8).isEven ? 0 : 8); x < size.width; x += 16) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImageCheckerboardPainter oldDelegate) =>
      pane != oldDelegate.pane || alternate != oldDelegate.alternate;
}
