"""Small compatibility nodes used by imported Comfy Fleet workflows.

These deliberately replace only dependency-free utility nodes. They avoid
installing large third-party packs for logic that does not need their model or
image-processing features.
"""

from __future__ import annotations

import json
import math
from typing import Any


class AnyType(str):
    def __ne__(self, other: object) -> bool:
        return False


ANY = AnyType("*")


class ImpactIfNone:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[AnyType]]]:
        return {"required": {}, "optional": {"signal": (ANY,), "any_input": (ANY,)}}

    RETURN_TYPES = (ANY, "BOOLEAN")
    RETURN_NAMES = ("signal_opt", "bool")
    FUNCTION = "evaluate"
    CATEGORY = "Comfy Fleet/Compatibility"

    def evaluate(self, signal: Any = None, any_input: Any = None) -> tuple[Any, bool]:
        return signal, any_input is not None


class ImpactCompare:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[Any, ...]]]:
        return {
            "required": {
                "a": (ANY,),
                "b": (ANY,),
                "cmp": (
                    [
                        "a = b",
                        "a != b",
                        "a > b",
                        "a < b",
                        "a >= b",
                        "a <= b",
                        "a is b",
                        "a is not b",
                    ],
                ),
            }
        }

    RETURN_TYPES = ("BOOLEAN",)
    FUNCTION = "compare"
    CATEGORY = "Comfy Fleet/Compatibility"

    def compare(self, a: Any, b: Any, cmp: str) -> tuple[bool]:
        operators = {
            "a = b": lambda: a == b,
            "a != b": lambda: a != b,
            "a > b": lambda: a > b,
            "a < b": lambda: a < b,
            "a >= b": lambda: a >= b,
            "a <= b": lambda: a <= b,
            "a is b": lambda: a is b,
            "a is not b": lambda: a is not b,
        }
        if cmp not in operators:
            raise ValueError(f"Unsupported comparison: {cmp}")
        return (bool(operators[cmp]()),)


class ToBasicPipe:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[AnyType]]]:
        return {
            "required": {
                "model": ("MODEL",),
                "clip": ("CLIP",),
                "vae": ("VAE",),
                "positive": ("CONDITIONING",),
                "negative": ("CONDITIONING",),
            }
        }

    RETURN_TYPES = ("BASIC_PIPE",)
    RETURN_NAMES = ("basic_pipe",)
    FUNCTION = "pack"
    CATEGORY = "Comfy Fleet/Compatibility"

    def pack(
        self,
        model: Any,
        clip: Any,
        vae: Any,
        positive: Any,
        negative: Any,
    ) -> tuple[tuple[Any, Any, Any, Any, Any]]:
        return ((model, clip, vae, positive, negative),)


class FromBasicPipe:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[str]]]:
        return {"required": {"basic_pipe": ("BASIC_PIPE",)}}

    RETURN_TYPES = ("MODEL", "CLIP", "VAE", "CONDITIONING", "CONDITIONING")
    RETURN_NAMES = ("model", "clip", "vae", "positive", "negative")
    FUNCTION = "unpack"
    CATEGORY = "Comfy Fleet/Compatibility"

    def unpack(self, basic_pipe: tuple[Any, ...]) -> tuple[Any, ...]:
        return tuple(basic_pipe)


class EditBasicPipe:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[AnyType]]]:
        return {
            "required": {"basic_pipe": ("BASIC_PIPE",)},
            "optional": {
                "model": ("MODEL",),
                "clip": ("CLIP",),
                "vae": ("VAE",),
                "positive": ("CONDITIONING",),
                "negative": ("CONDITIONING",),
            },
        }

    RETURN_TYPES = ("BASIC_PIPE",)
    RETURN_NAMES = ("basic_pipe",)
    FUNCTION = "edit"
    CATEGORY = "Comfy Fleet/Compatibility"

    def edit(
        self,
        basic_pipe: tuple[Any, ...],
        model: Any = None,
        clip: Any = None,
        vae: Any = None,
        positive: Any = None,
        negative: Any = None,
    ) -> tuple[tuple[Any, ...]]:
        replacements = (model, clip, vae, positive, negative)
        updated = tuple(
            current if replacement is None else replacement
            for current, replacement in zip(basic_pipe, replacements, strict=True)
        )
        return (updated,)


class AudioToFrameCount:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[Any, ...]]]:
        return {
            "required": {
                "audio": ("AUDIO",),
                "fps": ("FLOAT", {"default": 24.0, "min": 1.0, "max": 240.0}),
            }
        }

    RETURN_TYPES = ("INT",)
    RETURN_NAMES = ("frames",)
    FUNCTION = "count"
    CATEGORY = "Comfy Fleet/Compatibility"

    def count(self, audio: dict[str, Any], fps: float) -> tuple[int]:
        waveform = audio["waveform"]
        sample_rate = float(audio["sample_rate"])
        sample_count = int(waveform.shape[-1])
        return (max(1, math.ceil(sample_count / sample_rate * float(fps))),)


class FancyTimerNode:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, str]]:
        return {
            "required": {},
            "hidden": {"prompt": "PROMPT", "unique_id": "UNIQUE_ID"},
        }

    RETURN_TYPES: tuple[()] = ()
    FUNCTION = "execute"
    OUTPUT_NODE = True
    CATEGORY = "Comfy Fleet/Compatibility"

    def execute(self, **_: Any) -> dict[str, Any]:
        return {}


class SystemNotification:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[AnyType]]]:
        return {"required": {"any": (ANY,)}}

    RETURN_TYPES = (ANY,)
    FUNCTION = "passthrough"
    CATEGORY = "Comfy Fleet/Compatibility"

    def passthrough(self, any: Any) -> tuple[Any]:
        return (any,)


class JsonExtractString:
    """Legacy equivalent of ComfyUI's newer core JSON text extractor."""

    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[Any, ...]]]:
        return {
            "required": {
                "json_string": ("STRING", {"multiline": True}),
                "key": ("STRING", {"multiline": False}),
            }
        }

    RETURN_TYPES = ("STRING",)
    FUNCTION = "extract"
    CATEGORY = "Comfy Fleet/Compatibility"

    def extract(self, json_string: str, key: str) -> tuple[str]:
        try:
            data = json.loads(json_string)
        except (json.JSONDecodeError, TypeError):
            return ("",)
        if not isinstance(data, dict) or key not in data or data[key] is None:
            return ("",)
        return (str(data[key]),)


NODE_CLASS_MAPPINGS = {
    "ImpactIfNone": ImpactIfNone,
    "ImpactCompare": ImpactCompare,
    "ToBasicPipe": ToBasicPipe,
    "FromBasicPipe": FromBasicPipe,
    "EditBasicPipe": EditBasicPipe,
    "AudioToFrameCount": AudioToFrameCount,
    "FancyTimerNode": FancyTimerNode,
    "SystemNotification|pysssss": SystemNotification,
    "JsonExtractString": JsonExtractString,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "ImpactIfNone": "Input Present (Comfy Fleet)",
    "ImpactCompare": "Compare (Comfy Fleet)",
    "ToBasicPipe": "Build Basic Pipe (Comfy Fleet)",
    "FromBasicPipe": "Unpack Basic Pipe (Comfy Fleet)",
    "EditBasicPipe": "Edit Basic Pipe (Comfy Fleet)",
    "AudioToFrameCount": "Audio Frame Count (Comfy Fleet)",
    "FancyTimerNode": "Execution Timer (Compatibility)",
    "SystemNotification|pysssss": "Completion Signal (Compatibility)",
    "JsonExtractString": "Extract Text from JSON (Compatibility)",
}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]
