# Development container for cuda-oxide (https://github.com/NVIDIA/cuda-rust)
# Base: CUDA devel image (nvcc, CUDA headers, cuda-gdb, compute-sanitizer)
FROM nvidia/cuda:13.3.1-devel-ubuntu24.04

ARG LLVM_VERSION=21
ARG RUST_TOOLCHAIN=nightly-2026-10-11

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling. openssh-server is here for RunPod: both the ssh.runpod.io
# proxy and a directly exposed TCP port terminate at an sshd inside this
# container. The host keys the package generates at build time are deleted --
# start.sh regenerates them per container, so pods don't share one identity.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates pkg-config cmake \
    lsb-release software-properties-common gnupg sudo vim-tiny less \
    openssh-server python3 && \
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub && \
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

# Rust lives under /usr/local rather than a home directory: sshd builds a fresh
# environment per session, and /usr/local/cargo/bin on the PATH of PID 1 is
# what start.sh snapshots into /etc/container_env.sh for SSH logins.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo

# Pinned Rust nightly, with the full component set from cuda-oxide's
# rust-toolchain.toml: rust-src for cross-compiling std to NVPTX, rustc-dev for
# the codegen backend. Installing all of them here means rustup doesn't stop to
# fetch anything the first time you cd into a checkout.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain ${RUST_TOOLCHAIN} && \
    ${CARGO_HOME}/bin/rustup component add \
    rust-src rustc-dev llvm-tools rust-analyzer clippy rustfmt \
    --toolchain ${RUST_TOOLCHAIN}

ENV PATH="/usr/local/cargo/bin:/usr/local/cuda/bin:/root/.local/bin:${PATH}" \
    CUDA_TOOLKIT_PATH=/usr/local/cuda \
    CUDA_OXIDE_LLC=/usr/bin/llc-${LLVM_VERSION} \
    LIBCLANG_PATH=/usr/lib/llvm-${LLVM_VERSION}/lib \
    LLVM_CONFIG_PATH=/usr/bin/llvm-config-${LLVM_VERSION}

# The cargo-oxide CLI, installed into /usr/local/cargo/bin so it is on PATH
# outside a checkout too. Verbatim from the cuda-oxide README -- replace this
# whole command when upstream changes it. Tracks main, so a rebuild can pick up
# a different revision than the last one.
RUN cargo +nightly-2026-10-11 install --git https://github.com/NVIDIA/cuda-rust.git cargo-oxide

# Claude Code. The installer puts the launcher in $HOME/.local/bin, which for
# this image means /root/.local/bin -- already on PATH above. Like cargo-oxide
# this is unpinned: it installs whatever is current at build time.
RUN curl -fsSL https://claude.ai/install.sh | bash

# Key auth only, for root (the account RunPod logs you in as).
RUN mkdir -p /etc/ssh/sshd_config.d && \
    printf '%s\n' \
    'PermitRootLogin prohibit-password' \
    'PasswordAuthentication no' \
    'ClientAliveInterval 60' \
    > /etc/ssh/sshd_config.d/99-container.conf

# Source the environment start.sh snapshots at boot. profile.d covers
# interactive SSH logins; .bashrc covers `ssh <pod> <command>`, which is not a
# login shell but does read .bashrc when bash is started by sshd.
RUN printf '%s\n' '[ -f /etc/container_env.sh ] && . /etc/container_env.sh' \
    | tee /etc/profile.d/10-container-env.sh >> /root/.bashrc

# Fallback authorized key, used when RunPod doesn't inject $PUBLIC_KEY.
RUN mkdir -p /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRLJ4AqJNVc06km2X/g+pU9RAFeBYi+okJMgR8TfcmG shshemi@gmail.com' \
    >> /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys

COPY --chmod=755 start.sh /start.sh

# On RunPod this is the network volume mount point, and the only path that
# survives a pod restart -- keep checkouts here.
WORKDIR /workspace

EXPOSE 22

CMD ["/start.sh"]
