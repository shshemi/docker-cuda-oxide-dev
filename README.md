# cuda-oxide dev container

Development environment for [cuda-oxide](https://github.com/NVlabs/cuda-oxide):
CUDA 12.9 (devel), LLVM/Clang 21, and Rust `nightly-2026-04-03` with
`rust-src` + `rustc-dev`, matching the repo's `rust-toolchain.toml`.

Built on [`runpod/base`](https://github.com/runpod/containers), so it runs as a
RunPod pod out of the box: SSH, the pod environment, and the web terminal all
work without extra configuration.

## Build

```sh
docker build -t cuda-oxide-dev .
```

## Run on RunPod

Create a template pointing at `ghcr.io/<owner>/docker-cuda-oxide-dev:latest`
and leave **Container Start Command** empty — the image's own `CMD` is
`/start.sh` (inherited from `runpod/base`), which starts sshd and holds the
container open. Anything you type in that field replaces it and the pod will
exit immediately.

Add your public key under **Account → Settings → SSH Public Keys** before
starting the pod; RunPod passes it in as `$PUBLIC_KEY` and `/start.sh` writes
it to `/root/.ssh/authorized_keys`.

Proxy SSH works with no further setup:

```sh
ssh <pod-id>-<hash>@ssh.runpod.io -i ~/.ssh/id_ed25519
```

For a direct (non-proxied) connection, add TCP port `22` to the template's
**Expose TCP Ports** and deploy on a machine with a public IP. Ports cannot be
added to an already-running pod — the template has to be edited and the pod
recreated.

Only `/workspace` persists across pod restarts, so keep checkouts there.

## Run locally

Requires the NVIDIA Container Toolkit and an Ampere+ GPU (sm_80+). Pass an
explicit command to bypass `/start.sh`, which otherwise runs the pod services
and blocks:

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

## Notes

Rust is installed system-wide (`CARGO_HOME=/usr/local/cargo`,
`RUSTUP_HOME=/usr/local/rustup`) rather than in a home directory, because sshd
builds a fresh environment per session. `/start.sh` additionally snapshots the
pod environment to `/etc/rp_environment` and sources it from `~/.bashrc`, which
is how `PATH`, `CUDA_TOOLKIT_PATH`, and `CUDA_OXIDE_LLC` reach your shell.
