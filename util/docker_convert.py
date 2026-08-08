#!/usr/bin/env python3
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


PASSTHROUGH_COMMANDS = {
    "bash",
    "sh",
    "/bin/bash",
    "/bin/sh",
    "/usr/bin/bash",
    "/usr/bin/sh",
}


def list_devices():
    import torch

    if not torch.cuda.is_available():
        print("No CUDA devices available")
        return 0

    for idx in range(torch.cuda.device_count()):
        props = torch.cuda.get_device_properties(idx)
        total_gib = props.total_memory / (1024 ** 3)
        capability = f"{props.major}.{props.minor}"
        print(f"{idx}: {props.name}, {total_gib:.2f} GiB, compute capability {capability}")
    return 0


def handle_non_job_args(argv):
    if argv and argv[0] in PASSTHROUGH_COMMANDS:
        os.execvp(argv[0], argv)

    if argv in (["-d"], ["--list-devices"], ["--list_devices"]):
        return list_devices()
    return None


if __name__ == "__main__":
    handled = handle_non_job_args(sys.argv[1:])
    if handled is not None:
        raise SystemExit(handled)

    from exllamav3.conversion.convert_model import main, parser, prepare

    args = parser.parse_args()
    in_args, job_state, ok, err = prepare(args)
    if not ok:
        print(f" !! Error: {err}")
    else:
        main(in_args, job_state)
