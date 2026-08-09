#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/convert_exl3_docker.sh -i INPUT_DIR -o OUTPUT_DIR -w WORK_DIR -b BITS [options] [-- extra convert.py args]
  scripts/convert_exl3_docker.sh -i INPUT_DIR -o OUTPUT_DIR -w WORK_DIR --resume [options] [-- extra convert.py args]

Required for new conversions:
  -i, --input-dir DIR     Host path to the unquantized Hugging Face model
  -o, --output-dir DIR    Host path where the EXL3 model will be written
  -w, --work-dir DIR      Host path for temporary tensors and checkpoints
  -b, --bits BITS         Target average bits per weight, e.g. 3.75 or 4.0

Common options:
      --resume            Resume an interrupted conversion from WORK_DIR
      --hq                Increase bitrate of select layers
  -d, --devices LIST      ExLlamaV3 device list, e.g. 0,1,2
  -dr, --device-ratios L  ExLlamaV3 device ratios, e.g. 3,4,5
      --parallel-mode     Enable ExLlamaV3 parallel mode
      --shard-size MB     Output shard size in MB
      --head-bits BITS    Bits for lm_head, default is ExLlamaV3's default
      --override-anyway   Allow resume overrides that may break the existing job
      --cache-dir DIR     Host cache dir, default: ~/.cache/exllamav3-docker
      --selinux-label M   Add Docker SELinux volume label mode, usually z or Z
      --image NAME        Docker image name, default: exllamav3-convert
      --gpus VALUE        Docker --gpus value, default: all
      --dry-run           Print the docker command without running it
  -h, --help              Show this help

Any arguments after "--" are passed through to ExLlamaV3's converter.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

abs_existing_dir() {
    local path=$1
    [[ -d "$path" ]] || die "directory does not exist: $path"
    realpath "$path"
}

abs_path() {
    local path=$1
    realpath -m "$path"
}

input_dir=""
output_dir=""
work_dir=""
bits=""
image="exllamav3-convert"
cache_dir="${HOME}/.cache/exllamav3-docker"
selinux_label=""
gpus="all"
resume=0
dry_run=0
convert_args=()
passthrough=()

while (($#)); do
    case "$1" in
        -i|--input-dir)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            input_dir=$2
            shift 2
            ;;
        -o|--output-dir)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            output_dir=$2
            shift 2
            ;;
        -w|--work-dir)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            work_dir=$2
            shift 2
            ;;
        -b|--bits)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            bits=$2
            shift 2
            ;;
        --resume|-r)
            resume=1
            shift
            ;;
        --hq)
            convert_args+=("-hq")
            shift
            ;;
        -d|--devices)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            convert_args+=("-d" "$2")
            shift 2
            ;;
        -dr|--device-ratios)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            convert_args+=("-dr" "$2")
            shift 2
            ;;
        --parallel-mode)
            convert_args+=("-pm")
            shift
            ;;
        --shard-size)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            convert_args+=("-ss" "$2")
            shift 2
            ;;
        --head-bits)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            convert_args+=("-hb" "$2")
            shift 2
            ;;
        --override-anyway|--override_anyway)
            convert_args+=("--override_anyway")
            shift
            ;;
        --cache-dir)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            cache_dir=$2
            shift 2
            ;;
        --selinux-label)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            [[ "$2" == "z" || "$2" == "Z" ]] || die "--selinux-label must be z or Z"
            selinux_label=$2
            shift 2
            ;;
        --image)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            image=$2
            shift 2
            ;;
        --gpus)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            gpus=$2
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            passthrough=("$@")
            break
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$work_dir" ]] || die "--work-dir is required"

if (( resume == 0 )); then
    [[ -n "$input_dir" ]] || die "--input-dir is required for new conversions"
    [[ -n "$output_dir" ]] || die "--output-dir is required for new conversions"
    [[ -n "$bits" ]] || die "--bits is required for new conversions"
else
    [[ -n "$input_dir" ]] || die "--input-dir is required for resume so the original /input_model mount exists"
    [[ -n "$output_dir" ]] || die "--output-dir is required for resume so the original /output_base mount exists"
fi

work_dir=$(abs_path "$work_dir")
output_dir=$(abs_path "$output_dir")
cache_dir=$(abs_path "$cache_dir")

if (( dry_run == 0 )); then
    mkdir -p "$work_dir" "$output_dir" "$cache_dir"
fi

volume_suffix() {
    local suffix=$1
    if [[ -n "$selinux_label" ]]; then
        printf '%s,%s' "$suffix" "$selinux_label"
    else
        printf '%s' "$suffix"
    fi
}

rw_volume_suffix=$(volume_suffix "rw")
ro_volume_suffix=$(volume_suffix "ro")

docker_args=(
    docker run --rm
    --gpus "$gpus"
    -v "${work_dir}:/work:${rw_volume_suffix}"
    -v "${output_dir}:/output:${rw_volume_suffix}"
    -v "${cache_dir}:/cache:${rw_volume_suffix}"
)

converter_args=(
    -w /work
)

if (( resume == 1 )); then
    input_dir=$(abs_existing_dir "$input_dir")
    docker_args+=(-v "${input_dir}:/input_model:${ro_volume_suffix}")
    converter_args+=("-r")
else
    input_dir=$(abs_existing_dir "$input_dir")
    docker_args+=(-v "${input_dir}:/input_model:${ro_volume_suffix}")
    converter_args+=(
        -i /input_model
        -o /output
        -b "$bits"
    )
fi

converter_args+=("${convert_args[@]}" "${passthrough[@]}")
cmd=("${docker_args[@]}" "$image" "${converter_args[@]}")

printf 'Running:'
printf ' %q' "${cmd[@]}"
printf '\n'

if (( dry_run == 0 )); then
    exec "${cmd[@]}"
fi
