FROM ubuntu:22.04

ARG FLUTTER_VERSION
ARG FLUTTER_SHA256
ARG RUST_VERSION=1.97.1
# Keep the versioned download and checksum paired; continuous replaces its asset.
ARG APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
ARG GIT_VERSION=2.39.5
ARG GIT_SHA256=c58da92c378df4a986ca33266897a7397e86c22ee266a284d8c2432c39066b59

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/flutter/bin:/root/.cargo/bin:${PATH}"
# Release runners sit behind a flaky connection: every download retries.
ENV CARGO_NET_RETRY=10
ENV CURL_RETRY="--retry 6 --retry-all-errors --retry-delay 10 --connect-timeout 30"

RUN printf 'Acquire::Retries "6";\nAcquire::http::Timeout "60";\n' > /etc/apt/apt.conf.d/80-retries

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        binutils \
        ca-certificates \
        clang \
        cmake \
        cpio \
        curl \
        dpkg-dev \
        file \
        gcc \
        git \
        libcurl4-openssl-dev \
        libexpat1-dev \
        libfuse2 \
        libglu1-mesa \
        libgtk-3-dev \
        liblzma-dev \
        make \
        ninja-build \
        pkg-config \
        rpm \
        ruby-dev \
        unzip \
        xauth \
        xvfb \
        xz-utils \
        zip \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl $CURL_RETRY -fsSL \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Cross toolchain for the Linux arm64 remote helper: the same Ubuntu 22.04 glibc floor, and an
# emulator so the built helper can report its build.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        binutils-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        qemu-user \
    && rm -rf /var/lib/apt/lists/*

RUN curl $CURL_RETRY -fsSL \
        "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz" \
        -o /tmp/git.tar.xz \
    && echo "${GIT_SHA256}  /tmp/git.tar.xz" | sha256sum -c - \
    && mkdir /tmp/git-source \
    && tar -xJf /tmp/git.tar.xz -C /tmp/git-source --strip-components=1 \
    && make -C /tmp/git-source -j2 prefix=/usr/local NO_GETTEXT=YesPlease NO_TCLTK=YesPlease all \
    && make -C /tmp/git-source prefix=/usr/local NO_GETTEXT=YesPlease NO_TCLTK=YesPlease install \
    && rm -rf /tmp/git-source /tmp/git.tar.xz \
    && test "$(git --version)" = "git version ${GIT_VERSION}"

RUN retry() { for attempt in 1 2 3 4 5; do "$@" && return 0; sleep 15; done; return 1; } \
    && curl $CURL_RETRY --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && retry sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rm /tmp/rustup-init.sh \
    && retry rustup component add --toolchain "${RUST_VERSION}" rustfmt clippy \
    && retry rustup target add --toolchain "${RUST_VERSION}" aarch64-unknown-linux-gnu \
    && rustc --version \
    && cargo --version

RUN for attempt in 1 2 3 4 5; do gem install --no-document fpm -v 1.16.0 && break; sleep 15; done \
    && fpm --version

RUN curl $CURL_RETRY -fsSL -L \
        https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage \
        -o /usr/local/bin/appimagetool \
    && echo "${APPIMAGETOOL_SHA256}  /usr/local/bin/appimagetool" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/appimagetool

WORKDIR /work/Flutter/GitLama
