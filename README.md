# cuda-oxide dev container

Development environment for [cuda-oxide](https://github.com/NVlabs/cuda-oxide):
CUDA 12.9 (devel), LLVM/Clang 21, and Rust `nightly-2026-04-03` with
`rust-src` + `rustc-dev`, matching the repo's `rust-toolchain.toml`.

Runs as a RunPod pod: `start.sh` brings up sshd and holds the container open.

## Build

```sh
docker build -t cuda-oxide-dev .
```

## Run on RunPod

Create a template pointing at `ghcr.io/<owner>/docker-cuda-oxide-dev:latest`
and leave **Container Start Command** empty — anything typed there replaces the
image's `CMD ["/start.sh"]`, and without it the container exits immediately and
SSH fails with `container is not running`.

Add your public key under **Account → Settings → SSH Public Keys** before
starting the pod. RunPod passes it in as `$PUBLIC_KEY` and `start.sh` appends
it to `/root/.ssh/authorized_keys`.

Proxy SSH then works with no further setup:

```sh
ssh <pod-id>-<hash>@ssh.runpod.io -i ~/.ssh/id_ed25519
```

For a direct (non-proxied) connection, add TCP port `22` to the template's
**Expose TCP Ports** and deploy on a machine with a public IP. Ports can't be
added to a running pod — edit the template and recreate it.

Only `/workspace` persists across pod restarts, so keep checkouts there.

## Run locally

Requires the NVIDIA Container Toolkit and an Ampere+ GPU (sm_80+). Pass an
explicit command to bypass `start.sh`, which otherwise starts sshd and blocks:

```sh
git clone https://github.com/NVlabs/cuda-oxide.git   # if not already cloned
docker run --rm -it --gpus all \
  -v "$PWD/cuda-oxide:/workspace" \
  cuda-oxide-dev bash
```

## Inside the container

```sh
cargo oxide doctor        # verify the toolchain setup
cargo oxide run vecadd    # build + run an example on the GPU
cargo oxide sanitize vecadd
```

`cargo oxide` works as a workspace alias inside the repo. To install it
globally instead:

```sh
cargo +nightly-2026-04-03 install --git https://github.com/NVlabs/cuda-oxide.git cargo-oxide
```

## How the SSH setup works

`start.sh` runs as PID 1 and, in order:

1. **Generates host keys** (`ssh-keygen -A`). They are deliberately not baked
   into the image — a shared host key in a published image would let anyone who
   pulls it impersonate the pod. Existing keys are kept, so restarts don't
   invalidate `known_hosts`.
2. **Installs authorized keys** from `$PUBLIC_KEY`, appending and deduping so
   the fallback key baked into the image survives.
3. **Exports the environment** to `/etc/container_env.sh`. sshd builds a fresh
   environment per session, so without this, `PATH`, `CUDA_TOOLKIT_PATH`, and
   `CUDA_OXIDE_LLC` would be missing over SSH and `cargo` and `nvcc` would look
   uninstalled. `/etc/profile.d/10-container-env.sh` and `/root/.bashrc` source
   it.
4. **Starts sshd** in the background, logging to stderr so failures show up in
   `docker logs` and the RunPod log pane.
5. **Blocks** on `sleep infinity`, with a `SIGTERM` trap for a prompt shutdown.

sshd is backgrounded rather than run as `exec sshd -D` so that a failure in
sshd doesn't take the container down with it — the pod stays reachable through
RunPod's web terminal, which is where you'd debug it from. For the same reason
`start.sh` doesn't use `set -e`.

Rust is installed system-wide (`CARGO_HOME=/usr/local/cargo`,
`RUSTUP_HOME=/usr/local/rustup`) rather than under a home directory, for the
same environment reason.
