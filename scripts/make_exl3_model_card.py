#!/usr/bin/env python3
"""Generate a Hugging Face README add-in for EXL3 quantized models."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DEFAULT_TAGS = [
    "exl3",
    "exllamav3",
    "quantized",
]


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def strip_front_matter(text: str) -> str:
    if not text.startswith("---\n"):
        return text.lstrip()
    end = text.find("\n---\n", 4)
    if end == -1:
        return text.lstrip()
    return text[end + len("\n---\n") :].lstrip()


def strip_existing_addin(text: str) -> str:
    marker = "# Original Model Card:"
    index = text.find(marker)
    if index == -1:
        return strip_front_matter(text)
    lines = text[index:].splitlines()
    original_name = lines[0].split(":", 1)[1].strip()
    body = "\n".join(lines[1:]).lstrip()
    expected_heading = f"# {original_name}\n"
    while body.startswith(expected_heading):
        body = body[len(expected_heading) :].lstrip()
    return f"# {original_name}\n\n{body}"


def yaml_front_matter(base_model: str, pipeline_tag: str, tags: list[str]) -> str:
    lines = [
        "---",
        f"base_model: {base_model}",
        "base_model_relation: quantized",
        "library_name: exllamav3",
        "license: apache-2.0",
        f"pipeline_tag: {pipeline_tag}",
        "inference: false",
        "tags:",
    ]
    lines.extend(f"- {tag}" for tag in tags)
    lines.append("---")
    return "\n".join(lines) + "\n\n"


def quant_summary(quant_config: dict) -> dict[str, str]:
    calibration = quant_config.get("calibration") or {}
    return {
        "quantizer": f"exllamav3-{quant_config.get('version', 'unknown')}",
        "format": str(quant_config.get("quant_method", "exl3")),
        "bits": f"{float(quant_config.get('bits', 0.0)):.2f}",
        "head_bits": str(quant_config.get("head_bits", "unknown")),
        "calibration": f"{calibration.get('rows', 'unknown')} rows, {calibration.get('cols', 'unknown')} columns",
        "out_scales": str(quant_config.get("out_scales", "unknown")),
        "codebook": str(quant_config.get("codebook", "unknown")),
    }


def build_quantization_section(args: argparse.Namespace, heading: bool = True) -> str:
    root = Path(args.model_dir)
    quant_config = load_json(root / "quantization_config.json")
    config = load_json(root / "config.json")
    summary = quant_summary(quant_config)
    safetensors = sorted(root.glob("*.safetensors"))

    model_id = args.model_id
    dflash_config = config.get("dflash_config") or {}
    files_line = (
        f"{len(safetensors)} `.safetensors` file"
        if len(safetensors) == 1
        else f"{len(safetensors)} sharded `.safetensors` files"
    )

    lines = []
    if heading:
        lines.extend(["## Quantization", ""])
    lines.extend(
        [
            f"- Model: [{model_id}](https://huggingface.co/{model_id})",
            f'- Quantizer: `{summary["quantizer"]}`',
            f'- Format: `{summary["format"]}`',
            f'- Bits per weight: `{summary["bits"]}`',
            f'- Head bits: `{summary["head_bits"]}`',
            f'- Calibration: `{summary["calibration"]}`',
            f'- Output scales: `{summary["out_scales"]}`',
            f'- Codebook: `{summary["codebook"]}`',
            f"- Files: {files_line}",
        ]
    )
    if "block_size" in dflash_config:
        lines.insert(-1, f'- DFlash block size in config: `{dflash_config["block_size"]}`')
    return "\n".join(lines)


def build_readme(args: argparse.Namespace) -> str:
    root = Path(args.model_dir)
    readme_path = root / args.readme
    quant_config = load_json(root / "quantization_config.json")
    summary = quant_summary(quant_config)
    original_body = strip_existing_addin(readme_path.read_text(encoding="utf-8"))
    tags = list(dict.fromkeys(args.tags or DEFAULT_TAGS))

    original_body = original_body.replace(
        'src="assets/dflash_system.png"',
        f'src="https://huggingface.co/{args.model_id}/resolve/main/assets/dflash_system.png"',
    )
    title = args.title or (
        f"{args.model_id.split('/')[-1]} EXL3 {summary['bits']}bpw HB{summary['head_bits']}"
    )

    quantization_section = build_quantization_section(args)

    addin = f"""# {title}

This repository contains an EXL3 quantization of [{args.model_id}](https://huggingface.co/{args.model_id}) for ExLlamaV3.

{quantization_section}

## Compatibility

For the original model card and non-quantized weights, see [{args.model_id}](https://huggingface.co/{args.model_id}).

---

# Original Model Card: {args.model_id.split("/")[-1]}

"""
    return yaml_front_matter(args.model_id, args.pipeline_tag, tags) + addin + original_body


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", default=".", help="Model directory containing README.md and quantization_config.json.")
    parser.add_argument("--readme", default="README.md", help="README filename to update.")
    parser.add_argument("--model-id", required=True, help="Hugging Face model ID that was quantized.")
    parser.add_argument("--pipeline-tag", default="text-generation", help="Hugging Face pipeline tag.")
    parser.add_argument("--title", default=None, help="README title. Defaults to the model name with quantization details.")
    parser.add_argument("--tags", nargs="*", default=None, help="Override Hub tags.")
    parser.add_argument("--check", action="store_true", help="Print generated README without writing it.")
    parser.add_argument("--quant-only", action="store_true", help="Print only the model quantization summary without writing README.md.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.quant_only:
        print(build_quantization_section(args), end="\n")
        return
    readme = build_readme(args)
    if args.check:
        print(readme, end="")
        return
    path = Path(args.model_dir) / args.readme
    path.write_text(readme, encoding="utf-8")


if __name__ == "__main__":
    main()
