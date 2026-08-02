from __future__ import annotations

import base64
import binascii
import io
from pathlib import Path

from aiohttp import web
import numpy as np
from PIL import Image, ImageOps
import torch

import folder_paths
from server import PromptServer


@PromptServer.instance.routes.post("/comfy-fleet/cleanup-inputs")
async def cleanup_inputs(request: web.Request) -> web.Response:
    payload = await request.json()
    filenames = payload.get("filenames", []) if isinstance(payload, dict) else []
    input_root = Path(folder_paths.get_input_directory()).resolve()
    removed = 0
    if isinstance(filenames, list):
        for filename in filenames[:4]:
            if not isinstance(filename, str) or Path(filename).name != filename:
                continue
            candidate = (input_root / filename).resolve()
            if candidate.parent != input_root:
                continue
            try:
                candidate.unlink()
                removed += 1
            except FileNotFoundError:
                pass
    return web.json_response({"removed": removed})


@PromptServer.instance.routes.post("/comfy-fleet/cleanup-artifacts")
async def cleanup_artifacts(request: web.Request) -> web.Response:
    """Delete exact output/temp records immediately after successful transfer."""
    payload = await request.json()
    records = payload.get("records", []) if isinstance(payload, dict) else []
    roots = {
        "output": Path(folder_paths.get_output_directory()).resolve(),
        "temp": Path(folder_paths.get_temp_directory()).resolve(),
    }
    removed = 0
    if isinstance(records, list):
        for record in records[:16]:
            if not isinstance(record, dict):
                continue
            root = roots.get(record.get("type"))
            filename = record.get("filename")
            subfolder = record.get("subfolder", "")
            if root is None or not isinstance(filename, str) or Path(filename).name != filename:
                continue
            if not isinstance(subfolder, str) or Path(subfolder).is_absolute():
                continue
            candidate = (root / subfolder / filename).resolve()
            if candidate != root and root not in candidate.parents:
                continue
            try:
                candidate.unlink()
                removed += 1
            except FileNotFoundError:
                pass
    return web.json_response({"removed": removed})


class ComfyFleetLoadImageBase64:
    """Decode a transient image from the request body without writing a file."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"data": ("STRING", {"multiline": True})}}

    RETURN_TYPES = ("IMAGE", "MASK")
    FUNCTION = "decode"
    CATEGORY = "Comfy Fleet/Transient"

    def decode(self, data: str):
        try:
            payload = base64.b64decode(data, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("Invalid transient image encoding") from None
        with Image.open(io.BytesIO(payload)) as source:
            image = ImageOps.exif_transpose(source).convert("RGBA")
            pixels = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
            alpha = np.asarray(image.getchannel("A"), dtype=np.float32) / 255.0
        return (torch.from_numpy(pixels)[None, ...], 1.0 - torch.from_numpy(alpha))


class ComfyFleetLoadVideoBase64:
    """Decode transient video frames in RAM for brokered Vast requests."""

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "data": ("STRING", {"multiline": True}),
                "frame_load_cap": ("INT", {"default": 0, "min": 0, "max": 4096}),
            }
        }

    RETURN_TYPES = ("IMAGE", "INT")
    RETURN_NAMES = ("IMAGE", "frame_count")
    FUNCTION = "decode"
    CATEGORY = "Comfy Fleet/Transient"

    def decode(self, data: str, frame_load_cap: int):
        try:
            import av
            payload = base64.b64decode(data, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("Invalid transient video encoding") from None
        frames = []
        with av.open(io.BytesIO(payload)) as container:
            for frame in container.decode(video=0):
                frames.append(frame.to_ndarray(format="rgb24"))
                if frame_load_cap and len(frames) >= frame_load_cap:
                    break
        if not frames:
            raise ValueError("Transient video contained no decodable frames")
        pixels = np.stack(frames).astype(np.float32) / 255.0
        return (torch.from_numpy(pixels), len(frames))


class ComfyFleetSCAILSmokeInputs:
    """Create a deterministic in-memory motion fixture for worker benchmarks."""

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "width": ("INT", {"default": 256, "min": 128, "max": 1024, "step": 32}),
                "height": ("INT", {"default": 448, "min": 128, "max": 1024, "step": 32}),
                "frames": ("INT", {"default": 17, "min": 5, "max": 81, "step": 4}),
            }
        }

    RETURN_TYPES = ("IMAGE", "IMAGE", "IMAGE", "IMAGE")
    RETURN_NAMES = ("reference", "driving_video", "driving_mask", "reference_mask")
    FUNCTION = "create"
    CATEGORY = "Comfy Fleet/Testing"

    def create(self, width: int, height: int, frames: int):
        reference = np.full((height, width, 3), 0.18, dtype=np.float32)
        driving = np.full((frames, height, width, 3), 0.12, dtype=np.float32)
        driving_mask = np.zeros((frames, height, width, 3), dtype=np.float32)
        reference_mask = np.ones((height, width, 3), dtype=np.float32)
        color = np.array([0.85, 0.20, 0.30], dtype=np.float32)
        body_w, body_h = max(24, width // 5), max(64, height // 2)
        top = height // 4
        center = width // 2
        left = center - body_w // 2
        reference[top : top + body_h, left : left + body_w] = [0.72, 0.44, 0.24]
        reference_mask[top : top + body_h, left : left + body_w] = color
        for index in range(frames):
            offset = int((index / max(1, frames - 1) - 0.5) * width * 0.25)
            x0 = max(0, min(width - body_w, left + offset))
            driving[index, top : top + body_h, x0 : x0 + body_w] = [0.72, 0.44, 0.24]
            driving_mask[index, top : top + body_h, x0 : x0 + body_w] = color
        return (
            torch.from_numpy(reference)[None, ...],
            torch.from_numpy(driving),
            torch.from_numpy(driving_mask),
            torch.from_numpy(reference_mask)[None, ...],
        )


NODE_CLASS_MAPPINGS = {
    "ComfyFleetLoadImageBase64": ComfyFleetLoadImageBase64,
    "ComfyFleetLoadVideoBase64": ComfyFleetLoadVideoBase64,
    "ComfyFleetSCAILSmokeInputs": ComfyFleetSCAILSmokeInputs,
}
