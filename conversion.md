 Added scripts/convert_exl3_docker.sh.

  Use it like this:

  scripts/convert_exl3_docker.sh \
    -i /path/to/hf-model \
    -o /path/to/output/model-exl3-4.0bpw \
    -w /path/to/work/model-exl3-4.0bpw \
    -b 4.0

  Resume:

  scripts/convert_exl3_docker.sh \
    -i /path/to/hf-model \
    -o /path/to/output/model-exl3-4.0bpw \
    -w /path/to/work/model-exl3-4.0bpw \
    --resume

  Multi-GPU / higher quality:

  scripts/convert_exl3_docker.sh \
    -i /path/to/hf-model \
    -o /path/to/output/model-exl3-4.0bpw \
    -w /path/to/work/model-exl3-4.0bpw \
    -b 4.0 \
    --hq \
    --devices 0,1,2

  It creates the work/output/cache dirs, mounts the input read-only, and prints the exact docker run command before executing. I also updated doc/docker_convert.md with
  wrapper examples.

  Verified with bash -n and dry-run command generation.

