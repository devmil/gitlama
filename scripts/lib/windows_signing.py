"""Configuration policy shared by Windows release-signing tests and workflow."""

from __future__ import annotations

from urllib.parse import urlsplit


def signing_configuration(thumbprint: str | None,
                          timestamp_url: str | None) -> tuple[str, str] | None:
    thumbprint = (thumbprint or "").strip()
    timestamp_url = (timestamp_url or "").strip()
    if not thumbprint and not timestamp_url:
        return None
    if not thumbprint or not timestamp_url:
        raise ValueError("Windows signing thumbprint and timestamp URL must be configured together")
    if len(thumbprint) not in {40, 64} or any(character not in "0123456789abcdefABCDEF" for character in thumbprint):
        raise ValueError("Windows signing certificate thumbprint is invalid")
    parsed = urlsplit(timestamp_url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Windows timestamp URL must be unauthenticated HTTPS")
    return thumbprint, timestamp_url


def require_signing_results(configuration: tuple[str, str] | None,
                            verified: list[bool]) -> str:
    """Apply the no-fallback result policy used by the PowerShell signer."""
    if configuration is None:
        return "not-configured"
    if not verified or not all(verified):
        raise ValueError("configured Windows signing or verification failed")
    return "passed"
