import 'package:flutter/foundation.dart';

import '../models/host_platform.dart';

/// The platform this window runs on, for services that decide per platform.
HostPlatform hostPlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => HostPlatform.macOS,
  TargetPlatform.windows => HostPlatform.windows,
  TargetPlatform.linux => HostPlatform.linux,
  _ => HostPlatform.other,
};
