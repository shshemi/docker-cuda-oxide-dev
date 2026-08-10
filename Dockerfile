# Development container for cuda-oxide (https://github.com/NVlabs/cuda-oxide)
#
# Base: RunPod's official base image, itself built on
# nvidia/cuda:12.9-cudnn-devel-ubuntu24.04 (nvcc, CUDA headers, cuda-gdb,
# compute-sanitizer) plus the RunPod pod contract -- a /start.sh that installs
# $PUBLIC_KEY into authorized_keys, generates host keys, starts sshd, dumps the
# pod environment to /etc/rp_environment, and holds the container open with
# `sleep infinity`.
#
# Deliberately no CMD below: the inherited CMD ["/start.sh"] is what keeps the
# pod running and makes SSH work. Overriding it stops the container instantly
# and SSH fails with "container is not running".
FROM runpod/base:1.1.0-cuda1290-ubuntu2404

ARG LLVM_VERSION=21
ARG RUST_TOOLCHAIN=nightly-2026-04-03

ENV DEBIAN_FRONTEND=noninteractive

# Tools the RunPod base doesn't ship: pkg-config for Rust build scripts,
# lsb-release for apt.llvm.org's llvm.sh, less as a pager.
# (build-essential, cmake, git, curl, wget, gpg, sudo, vim and openssh-server
# all come from the base image.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    pkg-config lsb-release less && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# LLVM/Clang 21 from apt.llvm.org (Ubuntu 24.04 ships LLVM 18, which lacks
# the NVPTX intrinsics cuda-oxide needs for Hopper/Blackwell targets)
RUN wget -qO /tmp/llvm.sh https://apt.llvm.org/llvm.sh && \
    chmod +x /tmp/llvm.sh && \
    /tmp/llvm.sh ${LLVM_VERSION} && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev \
    clang-${LLVM_VERSION} libclang-${LLVM_VERSION}-dev \
    libclang-common-${LLVM_VERSION}-dev lld-${LLVM_VERSION} && \
    rm /tmp/llvm.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Make the versioned LLVM tools the defaults
RUN update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-${LLVM_VERSION}   100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 100 && \
    update-alternatives --install /usr/bin/llc     llc     /usr/bin/llc-${LLVM_VERSION}     100 && \
    update-alternatives --install /usr/bin/opt     opt     /usr/bin/opt-${LLVM_VERSION}     100

# Rust lives under /usr/local rather than /root/.cargo: sshd builds a fresh
# environment for each session, so a toolchain hidden in a home directory is
# easy to lose. /usr/local/cargo/bin is on PATH for PID 1, which RunPod's
# start.sh then re-exports to every shell via /etc/rp_environment.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo

# Pinned Rust nightly (matches cuda-oxide's rust-toolchain.toml):
# rust-src for cross-compiling std to NVPTX, rustc-dev for the codegen backend
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain ${RUST_TOOLCHAIN} && \
    ${CARGO_HOME}/bin/rustup component add rust-src rustc-dev llvm-tools rust-analyzer \
    --toolchain ${RUST_TOOLCHAIN}

ENV PATH="/usr/local/cargo/bin:${PATH}" \
    CUDA_TOOLKIT_PATH=/usr/local/cuda \
    CUDA_OXIDE_LLC=/usr/bin/llc-${LLVM_VERSION}

# On RunPod this is the network volume mount point, and the only path that
# survives a pod restart -- keep checkouts here.
WORKDIR /workspace
