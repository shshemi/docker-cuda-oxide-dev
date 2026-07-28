# cuda-oxide dev container

Development environment for [cuda-oxide](https://github.com/NVlabs/cuda-oxide):
CUDA 12.9 (devel), LLVM/Clang 21, and Rust `nightly-2026-04-03` with
`rust-src` + `rustc-dev`, matching the repo's `rust-toolchain.toml`.

## Build

```sh
docker build -t cuda-oxide-dev .
```

## Run

Requires the NVIDIA Container Toolkit on the host and an Ampere+ GPU (sm_80+).

```sh
git clone https://github.com/NVlabs/cuda-oxide.git   # if not already cloned
docker run --rm -it --gpus all \
  -v "$PWD/cuda-oxide:/workspace" \
  cuda-oxide-dev
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
