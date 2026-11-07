import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Visual tests capture ignored evidence under `build/evidence/`. Without
/// `--update-goldens` they compare against an earlier local capture, so a
/// checkout with no capture has nothing to compare and skips instead of
/// failing. [golden] is relative to `test/`, as in `matchesGoldenFile`.
bool visualCaptureSkip(String golden) =>
    !autoUpdateGoldenFiles && !File('test/$golden').existsSync();
