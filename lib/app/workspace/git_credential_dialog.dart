import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../app_theme.dart';

/// Credentials typed for one Git authentication retry. They are used once
/// and never stored.
final class GitCredentialInput {
  const GitCredentialInput({
    required this.secret,
    this.username,
    this.token = false,
  });

  /// Null when the person left the optional username empty.
  final String? username;

  /// The password, or the access token when [token] is set.
  final String secret;

  /// [secret] is an access token rather than a password.
  final bool token;
}

/// Asks for the credentials of a Git authentication retry (a clone or a
/// fetch, pull or push). Returns null when the person cancels.
///
/// The question must be answered explicitly: a click on the scrim does not
/// dismiss it; Escape and Cancel do.
Future<GitCredentialInput?> showGitCredentialDialog(
  BuildContext context, {
  String? target,
  bool allowToken = false,
}) => showMeridianDialog<GitCredentialInput>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      GitCredentialDialog(target: target, allowToken: allowToken),
);

/// The one credential form for Git authentication retries: the optional
/// [target] it authenticates to, a username, a password (or, when
/// [allowToken], an access token) and a single retry action that stays
/// disabled while the secret is empty.
class GitCredentialDialog extends StatefulWidget {
  const GitCredentialDialog({super.key, this.target, this.allowToken = false});

  /// The remote or URL being authenticated to, shown above the fields.
  final String? target;

  /// Offers "Use an access token" next to the password.
  final bool allowToken;

  @override
  State<GitCredentialDialog> createState() => _GitCredentialDialogState();
}

class _GitCredentialDialogState extends State<GitCredentialDialog> {
  final _username = TextEditingController();
  final _secret = TextEditingController();
  var _token = false;

  @override
  void dispose() {
    _username.clear();
    _secret.clear();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _valid => _secret.text.isNotEmpty;

  void _submit() {
    if (!_valid) return;
    final username = _username.text.trim();
    Navigator.pop(
      context,
      GitCredentialInput(
        username: username.isEmpty ? null : username,
        secret: _secret.text,
        token: widget.allowToken && _token,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.allowToken && _token;
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: context.l10n.transferCredentialsTitle,
      description: context.l10n.transferCredentialsTransient,
      onSubmit: _submit,
      submitDisabled: !_valid,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space5,
        children: [
          if (widget.target case final target?)
            Text(
              target,
              style: context.text.codeSm.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          MeridianTextField(
            fieldKey: const ValueKey('git-credential-username'),
            controller: _username,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            label: context.l10n.transferUsername,
          ),
          MeridianTextField(
            fieldKey: const ValueKey('git-credential-secret'),
            controller: _secret,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            label: !widget.allowToken
                ? context.l10n.clonePasswordOrToken
                : token
                ? context.l10n.transferToken
                : context.l10n.transferPassword,
            onChanged: (_) => setState(() {}),
          ),
          if (widget.allowToken)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianCheckbox(
                value: _token,
                label: context.l10n.transferUseToken,
                onChanged: (value) => setState(() => _token = value),
              ),
            ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          label: context.l10n.retryAuthentication,
          variant: MeridianButtonVariant.primary,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}
