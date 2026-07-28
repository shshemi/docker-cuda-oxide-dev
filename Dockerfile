# Development container for cuda-oxide (https://github.com/NVlabs/cuda-oxide)
# Base: CUDA devel image (nvcc, CUDA headers, cuda-gdb, compute-sanitizer)
FROM nvidia/cuda:12.9.1-devel-ubuntu24.04

ARG LLVM_VERSION=21
ARG RUST_TOOLCHAIN=nightly-2026-04-03

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates pkg-config cmake \
    lsb-release software-properties-common gnupg sudo vim-tiny less \
    python3 && \
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

# Non-root dev user (reuse the ubuntu user shipped with the base image)
RUN printf 'ubuntu ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu
ENV HOME=/home/ubuntu

# Pinned Rust nightly (matches cuda-oxide's rust-toolchain.toml):
# rust-src for cross-compiling std to NVPTX, rustc-dev for the codegen backend
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain ${RUST_TOOLCHAIN} && \
    $HOME/.cargo/bin/rustup component add rust-src rustc-dev llvm-tools rust-analyzer \
    --toolchain ${RUST_TOOLCHAIN}

ENV PATH="/home/ubuntu/.cargo/bin:/usr/local/cuda/bin:${PATH}" \
    CUDA_TOOLKIT_PATH=/usr/local/cuda \
    CUDA_OXIDE_LLC=/usr/bin/llc-${LLVM_VERSION}

WORKDIR /workspace

CMD ["/bin/bash"]
