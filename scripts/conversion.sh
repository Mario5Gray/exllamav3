#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/conversion.sh MODEL_ID -b BPW [--hq] --head-bits BITS [options]

  MODEL_ID is a Hugging Face model id, e.g. Qwen/Qwen3.8-27B

Required:
  -b, --bpw BPW           Target average bits per weight, e.g. 6.00
      --head-bits BITS    Bits for lm_head (6 or 8)

Options:
      --hq                Increase bitrate of select layers (passed to converter,
                           also appended to the derived output dir name)
      --input-base DIR    Base dir holding raw models (default: /media/f/fatmodels)
      --output-base DIR   Base dir for quantized output (default: /media/f/models)
      --work-base DIR     Base dir for docker work dirs (default: /media/f/workdir)
      --hf-org ORG        Hugging Face org/user to upload under (default: darkbit1001)
      --selinux-label M   Forwarded to convert_exl3_docker.sh (z or Z)
      --skip-upload       Run conversion + model card, skip hf upload
      --skip-card         Run conversion + upload, skip model card generation
      --dry-run           Forward --dry-run to the docker conversion step, and
                           skip chown / model card / upload
  -h, --help              Show this help
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

model_id=""
bpw=""
head_bits=""
hq=0
input_base="/media/f/fatmodels"
output_base="/media/f/models"
work_base="/media/f/workdir"
hf_org="darkbit1001"
selinux_label=""
skip_upload=0
skip_card=0
dry_run=0

while (($#)); do
    case "$1" in
        -b|--bpw)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            bpw=$2
            shift 2
            ;;
        --hq)
            hq=1
            shift
            ;;
        --head-bits)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            head_bits=$2
            shift 2
            ;;
        --input-base)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            input_base=$2
            shift 2
            ;;
        --output-base)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            output_base=$2
            shift 2
            ;;
        --work-base)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            work_base=$2
            shift 2
            ;;
        --hf-org)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            hf_org=$2
            shift 2
            ;;
        --selinux-label)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            selinux_label=$2
            shift 2
            ;;
        --skip-upload)
            skip_upload=1
            shift
            ;;
        --skip-card)
            skip_card=1
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            [[ -z "$model_id" ]] || die "unexpected argument: $1"
            model_id=$1
            shift
            ;;
    esac
done

[[ -n "$model_id" ]] || die "MODEL_ID is required"
[[ -n "$bpw" ]] || die "--bpw is required"
[[ -n "$head_bits" ]] || die "--head-bits is required"

bpw=$(printf '%.2f' "$bpw")
safe_model_id=${model_id//\//-}
hq_suffix=""
(( hq == 1 )) && hq_suffix="HQ"

out_name="${safe_model_id}-EXL3-${bpw}bpw-HB${head_bits}${hq_suffix}"

input_dir="${input_base}/${model_id}"
output_dir="${output_base}/${out_name}"
work_dir="${work_base}/${out_name}"

[[ -d "$input_dir" ]] || die "input model dir does not exist: $input_dir"

convert_cmd=(
    "${script_dir}/convert_exl3_docker.sh"
    -i "$input_dir"
    -o "$output_dir"
    -w "$work_dir"
    -b "$bpw"
    --head-bits "$head_bits"
)
(( hq == 1 )) && convert_cmd+=(--hq)
[[ -n "$selinux_label" ]] && convert_cmd+=(--selinux-label "$selinux_label")
(( dry_run == 1 )) && convert_cmd+=(--dry-run)

echo "== convert: ${model_id} -> ${output_dir}"
printf ' %q' "${convert_cmd[@]}"
printf '\n'
"${convert_cmd[@]}"

if (( dry_run == 1 )); then
    echo "== dry-run: skipping chown, model card, and upload"
    exit 0
fi

echo "== chown ${output_dir} to hdd:hdd"
sudo chown -R hdd:hdd "$output_dir"

if (( skip_card == 0 )); then
    echo "== model card"
    "${script_dir}/make_exl3_model_card.py" \
        --model-dir "$output_dir" \
        --model-id "$model_id"
fi

if (( skip_upload == 0 )); then
    echo "== hf upload"
    hf upload "${hf_org}/${out_name}" "$output_dir"
fi
