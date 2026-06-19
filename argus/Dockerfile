# Argus reproducible-environment image
#
# Pins every toolchain version Argus depends on so two runs against the same source
# tree on different machines produce identical Stage 3 PoC outputs.
#
# Build:   docker build -t argus:0.1.10 .
# Run:     scripts/run-in-docker.sh /path/to/rust/project
#
# Pinned versions are conservative; bump in lockstep with VERSION bumps and validate.

FROM rust:1.83.0-slim-bookworm AS argus-base

ARG SOLANA_VERSION=1.18.26
ARG ANCHOR_VERSION=0.30.1
ARG NODE_VERSION=20.18.0
ARG KANI_VERSION=0.56.0
ARG CARGO_FUZZ_VERSION=0.12.0

# System packages for Solana / Substrate / CosmWasm tooling
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libudev-dev \
    clang \
    cmake \
    protobuf-compiler \
    git \
    curl \
    jq \
    ca-certificates \
    bsdmainutils \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Add the wasm32 target for CosmWasm and Substrate
RUN rustup target add wasm32-unknown-unknown
RUN rustup component add rustfmt clippy
RUN rustup toolchain install nightly --component miri --component rustfmt

# Solana CLI (pinned)
RUN sh -c "$(curl -sSfL https://release.solana.com/v${SOLANA_VERSION}/install)" \
    && ln -s /root/.local/share/solana/install/active_release/bin/solana /usr/local/bin/solana \
    && ln -s /root/.local/share/solana/install/active_release/bin/solana-test-validator /usr/local/bin/solana-test-validator
ENV PATH="/root/.local/share/solana/install/active_release/bin:$PATH"

# Anchor via avm (pinned)
RUN cargo install --locked --version 0.31.1 avm \
    && avm install ${ANCHOR_VERSION} \
    && avm use ${ANCHOR_VERSION}
ENV PATH="/root/.avm/bin:$PATH"

# Node.js for Anchor TypeScript tests
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*
RUN npm install -g yarn

# Kani for Stage 3.5 (pinned)
RUN cargo install --locked --version ${KANI_VERSION} kani-verifier \
    && cargo kani setup

# cargo-fuzz for Stage 3.5
RUN cargo install --locked --version ${CARGO_FUZZ_VERSION} cargo-fuzz

# Argus skill (copied at build time; for runtime mount, use scripts/run-in-docker.sh)
WORKDIR /argus
COPY . /argus/
RUN bash /argus/install.sh

WORKDIR /workspace
ENTRYPOINT ["/bin/bash"]

# Default behavior: drop into shell with /workspace mounted from host.
# Use scripts/run-in-docker.sh as the convenience wrapper.
