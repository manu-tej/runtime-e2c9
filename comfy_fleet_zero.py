from __future__ import annotations

from pathlib import Path

from aiohttp import web

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


NODE_CLASS_MAPPINGS = {}
