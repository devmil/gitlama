#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="gitlama-linux-release:ubuntu-22.04-x86_64"
KEEP_STAGE=false
CONTAINER_ENGINE="${GITLAMA_CONTAINER_ENGINE:-}"
SOAK_SECONDS="${GITLAMA_SOAK_SECONDS:-0}"
# The Arch Linux package is built by makepkg in this image, beside the Ubuntu
# baseline that builds and qualifies everything else.
ARCH_IMAGE="${GITLAMA_ARCH_BUILD_IMAGE:-docker.io/library/archlinux:base-devel}"

[[ "$SOAK_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "Invalid Linux soak duration" >&2
  exit 1
}

# --remote-helper builds only the Linux x86_64 and arm64 remote helpers on the same baseline and
# leaves their archives and metadata in dist/remote-helper for the platform packages.
MODE=packages
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --keep-stage) KEEP_STAGE=true ;;
    --remote-helper) MODE=remote-helper ;;
    *)
      echo "Usage: $0 [--keep-stage] [--remote-helper]" >&2
      exit 2
      ;;
  esac
  shift
done
# The stage has no Git metadata, so the build identity travels explicitly. Client and helper
# must report the same commit.
SOURCE_COMMIT="${GITLAMA_SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid source commit for the release build" >&2
  exit 1
}
HELPER_INPUT="${GITLAMA_REMOTE_HELPER_DIR:-}"

cleanup() {
  status="$?"
  [[ -z "${GIT_ENV_FILE:-}" ]] || rm -f -- "$GIT_ENV_FILE"
  if [[ "$status" -ne 0 ]]; then
    # A failed qualification or soak still wrote its report; keep it for the
    # failure upload before the stage goes.
    for report in "$STAGE"/GitLama/dist/qualification/*.json; do
      [[ -f "$report" ]] || continue
      mkdir -p "$ROOT/dist/qualification"
      cp -- "$report" "$ROOT/dist/qualification/" || true
    done
  fi
  if [[ "$status" -ne 0 && "$KEEP_STAGE" == true ]]; then
    echo "Failed Linux release stage retained at: $STAGE" >&2
  else
    if ! rm -rf -- "$STAGE" 2>/dev/null; then
      # A rootful CI engine creates root-owned generated files in the bind
      # mount. Remove those files in the same container context, then remove
      # the now-empty host directory as the runner account.
      "$CONTAINER_ENGINE" run --rm \
        --platform linux/amd64 \
        --volume "$STAGE:/work$VOLUME_SUFFIX" \
        "$IMAGE" \
        bash -lc 'find /work -mindepth 1 -delete'
      rm -rf -- "$STAGE"
    fi
  fi
  return "$status"
}
STAGE="$(mktemp -d -t gitlama-linux-release.XXXXXX)"
trap cleanup EXIT

if [[ -z "$CONTAINER_ENGINE" ]]; then
  if command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  else
    echo "A Docker-compatible container engine is required" >&2
    exit 1
  fi
fi
command -v "$CONTAINER_ENGINE" >/dev/null 2>&1 || {
  echo "Container engine is unavailable: $CONTAINER_ENGINE" >&2
  exit 1
}
VOLUME_SUFFIX=""
case "$(basename "$CONTAINER_ENGINE")" in
  *podman*) VOLUME_SUFFIX=":Z" ;;
esac

mkdir -p "$STAGE/GitLama"
rsync -a \
  --exclude .git \
  --exclude build \
  --exclude dist \
  --exclude target \
  "$ROOT/" "$STAGE/GitLama/"
CONTAINER_HELPER=""
if [[ "$MODE" == packages && -n "$HELPER_INPUT" ]]; then
  mkdir -p "$STAGE/remote-helper"
  cp -- "$HELPER_INPUT"/gitlama-remote-helper-* "$STAGE/remote-helper/"
  CONTAINER_HELPER=/work/remote-helper
fi

# The image downloads Ubuntu packages, Qt, Git and Rust. A flaky connection fails a single
# attempt; cached layers make each retry resume where the last one stopped.
# CI provides GITHUB_TOKEN so GitHub API downloads avoid the shared anonymous rate limit.
BUILD_SECRETS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  BUILD_SECRETS=(--secret id=github_token,env=GITHUB_TOKEN)
fi
for attempt in 1 2 3; do
  if "$CONTAINER_ENGINE" build \
    --platform linux/amd64 \
    "${BUILD_SECRETS[@]}" \
    --file "$ROOT/tooling/linux-release/Dockerfile" \
    --tag "$IMAGE" \
    "$ROOT"; then
    break
  fi
  if [[ "$attempt" -eq 3 ]]; then
    echo "The Linux release image could not be built" >&2
    exit 1
  fi
  echo "Linux release image build failed; retrying (attempt $((attempt + 1)) of 3)" >&2
  sleep 30
done

# While the shared Git dependencies are private, CI forwards a step-scoped
# insteadOf rewrite (GIT_CONFIG_COUNT, GIT_CONFIG_KEY_0, GIT_CONFIG_VALUE_0)
# so Cargo inside the container can fetch them. A
# sudo-wrapped engine resets the environment, so the values travel in an
# owner-only env file rather than by inheritance or on the command line.
GIT_ENV_FILE="$(mktemp -t gitlama-linux-git-env.XXXXXX)"
chmod 0600 "$GIT_ENV_FILE"
for name in GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
  if [[ -n "${!name:-}" ]]; then
    printf '%s=%s\n' "$name" "${!name}" >> "$GIT_ENV_FILE"
  fi
done
if [[ "$MODE" == remote-helper ]]; then
  "$CONTAINER_ENGINE" run --rm \
    --platform linux/amd64 \
    --env SOURCE_DATE_EPOCH=0 \
    --env "GITLAMA_COLLECT_DIAGNOSTICS=${GITLAMA_COLLECT_DIAGNOSTICS:-0}" \
    --env "GITLAMA_SOURCE_COMMIT=$SOURCE_COMMIT" \
    --env-file "$GIT_ENV_FILE" \
    --volume "$STAGE:/work$VOLUME_SUFFIX" \
    --volume gitlama-linux-cargo-target:/work/GitLama/rust-core/target \
    --workdir /work/GitLama \
    "$IMAGE" \
    bash -lc 'set -euo pipefail
      for target in linux-x86_64 linux-arm64; do
        python3 scripts/package_remote_helper.py --target "$target" --output dist/remote-helper
      done
      if [[ "$GITLAMA_COLLECT_DIAGNOSTICS" == 1 ]]; then
        bash scripts/prepare-linux-diagnostics-handoff.sh /work dist/diagnostics
      fi'
  mkdir -p "$ROOT/dist/remote-helper"
  for file in "$STAGE"/GitLama/dist/remote-helper/gitlama-remote-helper-*; do
    [[ ! -e "$ROOT/dist/remote-helper/$(basename "$file")" ]] || {
      echo "Remote helper candidate already exists: $(basename "$file")" >&2
      exit 1
    }
    cp -- "$file" "$ROOT/dist/remote-helper/"
    printf '%s\n' "$ROOT/dist/remote-helper/$(basename "$file")"
  done
  if [[ "${GITLAMA_COLLECT_DIAGNOSTICS:-0}" == 1 ]]; then
    install -d -m 0700 -- "$ROOT/dist/diagnostics"
    for diagnostic in "$STAGE/GitLama/dist/diagnostics/"*-diagnostics.tar.gz; do
      [[ ! -e "$ROOT/dist/diagnostics/$(basename "$diagnostic")" ]] || { echo "Diagnostics already exist" >&2; exit 1; }
      cp "$diagnostic" "$ROOT/dist/diagnostics/"
    done
  fi
  exit 0
fi

"$CONTAINER_ENGINE" run --rm \
  --platform linux/amd64 \
  --env APPIMAGE_EXTRACT_AND_RUN=1 \
  --env "GITLAMA_SOURCE_COMMIT=$SOURCE_COMMIT" \
  --env "GITLAMA_REMOTE_HELPER_DIR=$CONTAINER_HELPER" \
  --env "GITLAMA_REQUIRE_REMOTE_HELPER=${GITLAMA_REQUIRE_REMOTE_HELPER:-0}" \
  --env "GITLAMA_SOAK_SECONDS=$SOAK_SECONDS" \
  --env SOURCE_DATE_EPOCH=0 \
  --env "GITLAMA_COLLECT_DIAGNOSTICS=${GITLAMA_COLLECT_DIAGNOSTICS:-0}" \
  --env-file "$GIT_ENV_FILE" \
  --volume "$STAGE:/work$VOLUME_SUFFIX" \
  --volume gitlama-linux-cargo-target:/work/GitLama/rust-core/target \
  --workdir /work/GitLama \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    cargo fetch --manifest-path rust-core/Cargo.toml --locked --target x86_64-unknown-linux-gnu
    python3 scripts/package.py AppImage
    python3 scripts/package.py deb --skip-build
    python3 scripts/package.py rpm --skip-build
    python3 scripts/package.py tar.gz --skip-build
  '

# makepkg refuses to run as root; the Arch container builds as an unprivileged
# user from the stripped bundle the Ubuntu build left in the stage.
"$CONTAINER_ENGINE" run --rm \
  --platform linux/amd64 \
  --env SOURCE_DATE_EPOCH=0 \
  --env "GITLAMA_REMOTE_HELPER_DIR=$CONTAINER_HELPER" \
  --env "GITLAMA_REQUIRE_REMOTE_HELPER=${GITLAMA_REQUIRE_REMOTE_HELPER:-0}" \
  --env "GITLAMA_SOURCE_COMMIT=$SOURCE_COMMIT" \
  --volume "$STAGE:/work$VOLUME_SUFFIX" \
  --workdir /work/GitLama \
  "$ARCH_IMAGE" \
  bash -lc '
    set -euo pipefail
    for attempt in 1 2 3 4 5; do pacman -Sy --noconfirm --needed python binutils && break; sleep 15; done
    useradd --create-home builder
    chown -R builder /work
    su builder -c "env SOURCE_DATE_EPOCH=0 GITLAMA_REMOTE_HELPER_DIR=$GITLAMA_REMOTE_HELPER_DIR \
      GITLAMA_REQUIRE_REMOTE_HELPER=$GITLAMA_REQUIRE_REMOTE_HELPER GITLAMA_SOURCE_COMMIT=$GITLAMA_SOURCE_COMMIT \
      python3 scripts/package.py pkg.tar.zst --skip-build"
    chown -R 0:0 /work
  '

"$CONTAINER_ENGINE" run --rm \
  --platform linux/amd64 \
  --env "GITLAMA_SOAK_SECONDS=$SOAK_SECONDS" \
  --env "GITLAMA_SOURCE_COMMIT=$SOURCE_COMMIT" \
  --env SOURCE_DATE_EPOCH=0 \
  --env "GITLAMA_COLLECT_DIAGNOSTICS=${GITLAMA_COLLECT_DIAGNOSTICS:-0}" \
  --volume "$STAGE:/work$VOLUME_SUFFIX" \
  --volume gitlama-linux-cargo-target:/work/GitLama/rust-core/target \
  --workdir /work/GitLama \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    python3 scripts/qualify-linux-packages.py dist --launch-seconds 4
    if [[ "$GITLAMA_COLLECT_DIAGNOSTICS" == 1 ]]; then
      version="$(sed -n "1p" VERSION)"
      build="$(sed -n "2p" VERSION)"
      python3 scripts/collect-debug-symbols.py --unit linux-x86_64 \
        --bundle build/linux/bundle \
        --search rust-core/target/release \
        --package "dist/GitLama-${version}-${build}-linux-x86_64.AppImage" \
        --package "dist/gitlama_${version}-${build}_amd64.deb" \
        --package "dist/gitlama-${version}-${build}.x86_64.rpm" \
        --package "dist/gitlama-${version}-${build}-x86_64.pkg.tar.zst" \
        --package "dist/GitLama-${version}-${build}-linux-x86_64.tar.gz"
      bash scripts/prepare-linux-diagnostics-handoff.sh /work dist/diagnostics
    fi
    if [[ "$GITLAMA_SOAK_SECONDS" -gt 0 ]]; then
      version="$(sed -n "1p" VERSION)"
      build="$(sed -n "2p" VERSION)"
      soak_root="$(mktemp -d /tmp/gitlama-linux-soak-package.XXXXXX)"
      trap '\''rm -rf -- "$soak_root"'\'' EXIT
      tar -xzf "dist/GitLama-${version}-${build}-linux-x86_64.tar.gz" -C "$soak_root"
      python3 scripts/soak-linux.py "$soak_root/gitlama/gitlama" \
        --duration-seconds "$GITLAMA_SOAK_SECONDS" \
        --report dist/qualification/linux-soak-x86_64.json
    fi
  '

VERSION="$(sed -n '1p' "$ROOT/VERSION")"
BUILD="$(sed -n '2p' "$ROOT/VERSION")"
ARTIFACTS=(
  "GitLama-${VERSION}-${BUILD}-linux-x86_64.AppImage"
  "gitlama_${VERSION}-${BUILD}_amd64.deb"
  "gitlama-${VERSION}-${BUILD}.x86_64.rpm"
  "gitlama-${VERSION}-${BUILD}-x86_64.pkg.tar.zst"
  "GitLama-${VERSION}-${BUILD}-linux-x86_64.tar.gz"
)

mkdir -p "$ROOT/dist/qualification"
for artifact in "${ARTIFACTS[@]}"; do
  [[ ! -e "$ROOT/dist/$artifact" ]] || {
    echo "Candidate already exists: dist/$artifact" >&2
    exit 1
  }
  cp "$STAGE/GitLama/dist/$artifact" "$ROOT/dist/$artifact"
done
cp "$STAGE/GitLama/dist/qualification/linux-x86_64.json" \
  "$ROOT/dist/qualification/linux-x86_64.json"
if [[ -f "$STAGE/GitLama/dist/qualification/linux-soak-x86_64.json" ]]; then
  cp "$STAGE/GitLama/dist/qualification/linux-soak-x86_64.json" \
    "$ROOT/dist/qualification/linux-soak-x86_64.json"
fi

printf '%s\n' "${ARTIFACTS[@]/#/$ROOT/dist/}"
printf '%s\n' "$ROOT/dist/qualification/linux-x86_64.json"

if [[ "${GITLAMA_COLLECT_DIAGNOSTICS:-0}" == 1 ]]; then
  install -d -m 0700 -- "$ROOT/dist/diagnostics"
  for diagnostic in "$STAGE/GitLama/dist/diagnostics/"*-diagnostics.tar.gz; do
    [[ ! -e "$ROOT/dist/diagnostics/$(basename "$diagnostic")" ]] || { echo "Diagnostics already exist" >&2; exit 1; }
    cp "$diagnostic" "$ROOT/dist/diagnostics/"
  done
fi
