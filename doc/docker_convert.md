# EXL3 Conversion Docker Image

This Docker image installs Python 3.12, PyTorch, and the local ExLlamaV3 checkout, then runs the EXL3 model conversion script for converting Hugging Face-format models to EXL3.

## Build

From the repository root:

```sh
docker build -f Dockerfile.convert -t exllamav3-convert .
```

The default base image is `nvidia/cuda:13.0.2-cudnn-devel-ubuntu24.04`. The Dockerfile creates a Python 3.12 virtual environment, installs `torch==2.11.0` from the PyTorch CUDA 13.0 wheel index, then installs ExLlamaV3 from the local repository contents. To pin a different PyTorch version:

```sh
docker build \
  --build-arg TORCH_VERSION=2.11.0 \
  -f Dockerfile.convert \
  -t exllamav3-convert .
```

If you change the CUDA image, also use a PyTorch CUDA wheel index with a matching CUDA version. CUDA 13.x minor compatibility can allow newer 13.x runtimes on older 13.x drivers, but a CUDA 13.0 base is the conservative choice for hosts whose driver reports CUDA 13.0.

## Convert A Model

The easiest path is the host-side wrapper:

```sh
scripts/convert_exl3_docker.sh \
  -i /path/to/models/llama3.1-8b-instruct \
  -o /path/to/exl3-output/llama3.1-8b-instruct-exl3-4.0bpw \
  -w /path/to/exl3-work/llama3.1-8b-instruct-exl3-4.0bpw \
  -b 4.0
```

It mounts the input model read-only, creates the output/work/cache directories as needed, and passes stable container paths to the converter.

Resume with:

```sh
scripts/convert_exl3_docker.sh \
  -i /path/to/models/llama3.1-8b-instruct \
  -o /path/to/exl3-output/llama3.1-8b-instruct-exl3-4.0bpw \
  -w /path/to/exl3-work/llama3.1-8b-instruct-exl3-4.0bpw \
  --resume
```

Pass extra converter arguments after `--`, or use built-in wrapper flags such as `--hq`, `--devices 0,1,2`, `--device-ratios 3,4,5`, and `--parallel-mode`.

On SELinux-enforcing hosts, add a Docker volume label mode:

```sh
scripts/convert_exl3_docker.sh \
  -i /path/to/models/llama3.1-8b-instruct \
  -o /path/to/exl3-output/llama3.1-8b-instruct-exl3-4.0bpw \
  -w /path/to/exl3-work/llama3.1-8b-instruct-exl3-4.0bpw \
  -b 4.0 \
  --selinux-label z
```

Use `z` for shared container access, which is usually the right choice for conversion directories. Use `Z` only when the mounted directories should be private to this one container label.

## Raw Docker

Mount your model, output, work, and cache directories. The container entrypoint runs the conversion wrapper, so pass the normal `convert.py` arguments directly:

```sh
docker run --rm --gpus all \
  -v /path/to/models:/models \
  -v /path/to/exl3-work/llama3.1-8b-instruct-exl3-4.0bpw:/work \
  -v /path/to/exl3-output/llama3.1-8b-instruct-exl3-4.0bpw:/output \
  -v /path/to/cache:/cache \
  exllamav3-convert \
  -i /models/llama3.1-8b-instruct \
  -o /output \
  -w /work \
  -b 4.0
```

The working directory stores checkpoints and temporary tensors, and should have enough free space for roughly one full copy of the output model.

## Resume An Interrupted Conversion

Use the same work directory and pass `-r`:

```sh
docker run --rm --gpus all \
  -v /path/to/models:/models \
  -v /path/to/exl3-work/llama3.1-8b-instruct-exl3-4.0bpw:/work \
  -v /path/to/exl3-output/llama3.1-8b-instruct-exl3-4.0bpw:/output \
  -v /path/to/cache:/cache \
  exllamav3-convert \
  -w /work \
  -r
```

## Multi-GPU Conversion

Use `--gpus all` and pass ExLlamaV3's device list:

```sh
docker run --rm --gpus all \
  -v /path/to/models:/models \
  -v /path/to/exl3-work/qwen3.5-35b-a3b-exl3-4.0bpw:/work \
  -v /path/to/exl3-output/qwen3.5-35b-a3b-exl3-4.0bpw:/output \
  -v /path/to/cache:/cache \
  exllamav3-convert \
  -i /models/qwen3.5-35b-a3b \
  -o /output \
  -w /work \
  -b 4.0 \
  -hq \
  -d 0,1,2
```

## Help

```sh
docker run --rm --gpus all exllamav3-convert -h
```

List visible CUDA devices without starting a conversion job:

```sh
docker run --rm --gpus all exllamav3-convert -d
```

For conversion jobs, `-d` still accepts ExLlamaV3's device list, e.g. `-d 0,1,2`.

Open an interactive shell in the image:

```sh
docker run --rm --gpus all -it exllamav3-convert /bin/bash
```

The wrapper recognizes `bash`, `sh`, `/bin/bash`, and `/bin/sh` before importing ExLlamaV3, so shell startup does not trigger converter or native extension setup.

## Notes

- The host must have a working NVIDIA driver and NVIDIA Container Toolkit.
- The ExLlamaV3 package version comes from the local `exllamav3/version.py`.
- The image uses a CUDA devel base because ExLlamaV3 may need CUDA and C++ build tooling for native extensions.
- Keep `/cache` mounted between runs so Hugging Face cache files can be reused.
- If SELinux denies writes to mounted directories, use `--selinux-label z` with the wrapper or add `:z` to raw Docker bind mounts.
