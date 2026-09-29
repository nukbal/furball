import argparse
import os
import shutil
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as functional


class SRVGGNetCompact(nn.Module):
    def __init__(self, scale):
        super().__init__()
        layers = [nn.Conv2d(3, 64, 3, 1, 1), nn.PReLU(64)]
        for _ in range(16):
            layers.extend((nn.Conv2d(64, 64, 3, 1, 1), nn.PReLU(64)))
        layers.append(nn.Conv2d(64, 3 * scale * scale, 3, 1, 1))
        self.body = nn.Sequential(*layers)
        self.scale = scale

    def forward(self, image):
        residual = functional.interpolate(image, scale_factor=self.scale, mode="nearest")
        return functional.pixel_shuffle(self.body(image), self.scale) + residual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--scale", required=True, type=int, choices=(2, 4))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    torch.set_num_threads(max(1, min(4, os.cpu_count() or 1)))
    checkpoint = torch.load(args.weights, map_location="cpu", weights_only=False)
    model = SRVGGNetCompact(args.scale).eval()
    model.load_state_dict(checkpoint["params"], strict=True)

    example = torch.zeros((1, 3, 522, 522), dtype=torch.float32)
    traced = torch.jit.trace(model, example, strict=True)
    converted = ct.convert(
        traced,
        source="pytorch",
        convert_to="mlprogram",
        inputs=[ct.TensorType(name="input", shape=example.shape, dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS15,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = args.output.with_name(args.output.stem + ".building.mlpackage")
    if temporary_output.exists():
        shutil.rmtree(temporary_output)
    if args.output.exists():
        shutil.rmtree(args.output)
    converted.save(str(temporary_output))
    temporary_output.rename(args.output)


if __name__ == "__main__":
    main()
