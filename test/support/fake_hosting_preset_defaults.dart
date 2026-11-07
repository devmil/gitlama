import 'package:gitlama/models/hosting.dart';

/// A test stand-in for the native preset rules (`hosting_preset_defaults`).
/// It covers the inputs the widget tests enter; the rules themselves are
/// tested in Rust and devmil-git.
HostingPresetDefaults? fakeHostingPresetDefaults(
  HostingPreset preset, {
  String? webBase,
}) {
  final fixed = switch (preset) {
    HostingPreset.gitHub => ('https://github.com', 'https://api.github.com'),
    HostingPreset.gitLab => ('https://gitlab.com', 'https://gitlab.com/api/v4'),
    HostingPreset.codeberg => (
      'https://codeberg.org',
      'https://codeberg.org/api/v1',
    ),
    _ => null,
  };
  final String web;
  final String api;
  var tenant = false;
  if (fixed != null) {
    (web, api) = fixed;
  } else {
    final raw = webBase?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (raw.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty) {
      return null;
    }
    web = 'https://${uri.authority.toLowerCase()}';
    final host = uri.host.toLowerCase();
    final label = host.endsWith('.ghe.com')
        ? host.substring(0, host.length - '.ghe.com'.length)
        : '';
    tenant =
        preset == HostingPreset.gitHubEnterprise &&
        label.isNotEmpty &&
        !label.contains('.');
    api = switch (preset) {
      HostingPreset.gitLabSelfManaged => '$web/api/v4',
      HostingPreset.gitHubEnterprise when tenant => 'https://api.$host',
      HostingPreset.gitHubEnterprise => '$web/api/v3',
      _ => '$web/api/v1',
    };
  }
  final github =
      preset == HostingPreset.gitHub ||
      preset == HostingPreset.gitHubEnterprise;
  final gitlab =
      preset == HostingPreset.gitLab ||
      preset == HostingPreset.gitLabSelfManaged;
  return HostingPresetDefaults(
    preset: preset,
    webBaseUrl: web,
    apiBaseUrl: api,
    gitHubTenant: tenant,
    capabilities: [
      HostingCapability.changeRequests,
      HostingCapability.changeRequestCheckout,
      HostingCapability.commitStatuses,
      HostingCapability.issues,
      HostingCapability.remoteReferences,
      if (github) HostingCapability.checkRuns,
    ],
    authentications: [
      HostingAuthentication.oauth,
      if (github) HostingAuthentication.gitHubCli,
      if (gitlab) HostingAuthentication.gitLabCli,
    ],
  );
}
