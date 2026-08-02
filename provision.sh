#!/usr/bin/env bash
set -Eeuo pipefail

# Public, immutable model/runtime provisioning for the isolated LTX 2.3 worker.
# User prompts, references, histories, and outputs are never written here.

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
COMFY_DIR="${WORKSPACE_DIR}/ComfyUI"
MODEL_DIR="${COMFY_DIR}/models"
PYTHON_BIN="/venv/main/bin/python"
RUNTIME_BUNDLE_REF="${RUNTIME_BUNDLE_REF:?RUNTIME_BUNDLE_REF must pin the public runtime bundle}"
BUNDLE_BASE="https://raw.githubusercontent.com/manu-tej/runtime-e2c9/${RUNTIME_BUNDLE_REF}"
MODEL_LOG="${MODEL_LOG:-/var/log/portal/comfyui.log}"

mkdir -p "$(dirname "$MODEL_LOG")" "$MODEL_DIR"/{diffusion_models,text_encoders,vae,latent_upscale_models,loras}

log() {
  printf '[ltx23-provision] %s\n' "$*" | tee -a "$MODEL_LOG"
}

fail() {
  log "ERROR at line $1"
}
trap 'fail $LINENO' ERR

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

if ! command -v aria2c >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aria2 unzip
  rm -rf /var/lib/apt/lists/*
fi

clone_at() {
  local url="$1"
  local revision="$2"
  local destination="$3"
  rm -rf "$destination"
  git clone --quiet "$url" "$destination"
  git -C "$destination" checkout --quiet "$revision"
}

install_requirements() {
  local path="$1"
  if [[ -f "$path" ]]; then
    "$PYTHON_BIN" -m pip install --no-cache-dir -q -r "$path"
  fi
}

download_asset() {
  local relative="$1"
  local url="$2"
  local expected_size="$3"
  local destination="$MODEL_DIR/$relative"
  local partial="${destination}.partial"

  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]] && [[ "$(stat -c %s "$destination")" == "$expected_size" ]]; then
    log "cached $relative"
    return 0
  fi

  # Preserve aria2's partial data and control file across provider reboots and
  # provisioning retries. If the control file is missing, a sparse partial
  # cannot be resumed safely because its completed segment map is unknown.
  if [[ -f "$partial" && ! -f "${partial}.aria2" ]]; then
    rm -f "$partial"
  fi
  log "downloading $relative"
  aria2c \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --continue=true \
    --file-allocation=none \
    --max-connection-per-server=16 \
    --min-split-size=16M \
    --quiet=true \
    --split=16 \
    --dir="$(dirname "$destination")" \
    --out="$(basename "$partial")" \
    "$url"

  local actual_size
  actual_size="$(stat -c %s "$partial")"
  if [[ "$actual_size" != "$expected_size" ]]; then
    log "size mismatch for $relative: $actual_size != $expected_size"
    return 1
  fi
  mv "$partial" "$destination"
}

log "installing pinned custom nodes"
CUSTOM_NODES="$COMFY_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES"

clone_at https://github.com/Lightricks/ComfyUI-LTXVideo.git 3b9c5cde4700917074823d45e25401d81049f8fc "$CUSTOM_NODES/ComfyUI-LTXVideo"
curl -fsSL "$BUNDLE_BASE/ltxvideo-kornia-pad.patch" -o /tmp/ltxvideo-kornia-pad.patch
git -C "$CUSTOM_NODES/ComfyUI-LTXVideo" apply /tmp/ltxvideo-kornia-pad.patch
clone_at https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git fe09f73756df202d08341c66b4dc5fc8d2acca22 "$CUSTOM_NODES/WhatDreamsCost-ComfyUI"
clone_at https://github.com/kijai/ComfyUI-KJNodes.git 4d46ac107c33ed8a3d181b8776ede66498583380 "$CUSTOM_NODES/ComfyUI-KJNodes"
clone_at https://github.com/rgthree/rgthree-comfy.git 6b76ee6f2c5a007710b5a16f97c94330d6ecc871 "$CUSTOM_NODES/rgthree-comfy"
clone_at https://github.com/yolain/ComfyUI-Easy-Use.git b5e31ef12ad9d0b187b545c2707735cc7d581c52 "$CUSTOM_NODES/ComfyUI-Easy-Use"
clone_at https://github.com/chrisgoringe/cg-use-everywhere.git 50ae9f8c5d8b9538589663c90a15d4067a02969c "$CUSTOM_NODES/cg-use-everywhere"
clone_at https://github.com/Azornes/Comfyui-Resolution-Master.git b47aaf485aff6e3ef0242153212d66af489d763b "$CUSTOM_NODES/Comfyui-Resolution-Master"
clone_at https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git 609f3afaa74b2f88ef9ce8d939626065e3247469 "$CUSTOM_NODES/ComfyUI-Custom-Scripts"

rm -rf "$CUSTOM_NODES/ComfyUI-VideoHelperSuite" "$CUSTOM_NODES/ComfyUI-MelBandRoFormer" "$CUSTOM_NODES/TTS-Audio-Suite"
mkdir -p "$CUSTOM_NODES/ComfyUI-VideoHelperSuite" "$CUSTOM_NODES/ComfyUI-MelBandRoFormer" "$CUSTOM_NODES/TTS-Audio-Suite"
curl -fsSL https://cdn.comfy.org/kosinkadink/comfyui-videohelpersuite/1.7.9/node.zip -o /tmp/vhs.zip
curl -fsSL https://cdn.comfy.org/kijai/ComfyUI-MelBandRoFormer/1.0.1/node.zip -o /tmp/mel.zip
curl -fsSL https://cdn.comfy.org/diogod/tts_audio_suite/4.26.2/node.zip -o /tmp/tts.zip
unzip -q /tmp/vhs.zip -d "$CUSTOM_NODES/ComfyUI-VideoHelperSuite"
unzip -q /tmp/mel.zip -d "$CUSTOM_NODES/ComfyUI-MelBandRoFormer"
unzip -q /tmp/tts.zip -d "$CUSTOM_NODES/TTS-Audio-Suite"

mkdir -p "$CUSTOM_NODES/comfy_fleet_compat" "$CUSTOM_NODES/comfy_fleet_zero"
curl -fsSL "$BUNDLE_BASE/comfy_fleet_compat.py" -o "$CUSTOM_NODES/comfy_fleet_compat/__init__.py"
curl -fsSL "$BUNDLE_BASE/comfy_fleet_zero.py" -o "$CUSTOM_NODES/comfy_fleet_zero/__init__.py"

install_requirements "$CUSTOM_NODES/ComfyUI-LTXVideo/requirements.txt"
install_requirements "$CUSTOM_NODES/ComfyUI-KJNodes/requirements.txt"
install_requirements "$CUSTOM_NODES/ComfyUI-Easy-Use/requirements.txt"
install_requirements "$CUSTOM_NODES/ComfyUI-VideoHelperSuite/requirements.txt"
install_requirements "$CUSTOM_NODES/ComfyUI-MelBandRoFormer/requirements.txt"

log "downloading pinned public model pack"
download_asset diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors https://huggingface.co/Kijai/LTX2.3_comfy/resolve/6d980fde0d330f2fed6ff8dfdfddb06d88a004e5/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors 25226571988 &
pids=("$!")
download_asset text_encoders/gemma_3_12B_it_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/ltx-2/resolve/bd5f9c87fcb0360ae7112f9784562670894d9492/split_files/text_encoders/gemma_3_12B_it_fp8_scaled.safetensors 13205434827 &
pids+=("$!")
download_asset text_encoders/ltx-2.3_text_projection_bf16.safetensors https://huggingface.co/Kijai/LTX2.3_comfy/resolve/6d980fde0d330f2fed6ff8dfdfddb06d88a004e5/text_encoders/ltx-2.3_text_projection_bf16.safetensors 2312149072 &
pids+=("$!")
download_asset vae/LTX23_video_vae_bf16.safetensors https://huggingface.co/Kijai/LTX2.3_comfy/resolve/6d980fde0d330f2fed6ff8dfdfddb06d88a004e5/vae/LTX23_video_vae_bf16.safetensors 1452258578 &
pids+=("$!")
download_asset vae/LTX23_audio_vae_bf16.safetensors https://huggingface.co/Kijai/LTX2.3_comfy/resolve/6d980fde0d330f2fed6ff8dfdfddb06d88a004e5/vae/LTX23_audio_vae_bf16.safetensors 364855188 &
pids+=("$!")
download_asset latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors https://huggingface.co/Lightricks/LTX-2.3/resolve/4229404625088d21c4f112eb640fb04a0900ee25/ltx-2.3-spatial-upscaler-x2-1.1.safetensors 995743560 &
pids+=("$!")
download_asset loras/LTX2.3/ltx-2.3-id-lora-talkvid-3k.safetensors https://huggingface.co/AviadDahan/LTX-2.3-ID-LoRA-TalkVid-3K/resolve/6eabedadefbcfa6c95092d50006629d9413102fd/lora_weights.safetensors 1157884304 &
pids+=("$!")
download_asset loras/LTX2.3/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/b4d1c4d8c9e544e9bbbd6811bb4363708b6093ff/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors 654465352 &
pids+=("$!")
download_asset loras/LTX2/ltx-2-19b-ic-lora-detailer.safetensors https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/4c385b23dabce40736f37454ef8887f177ce96b0/ltx-2-19b-ic-lora-detailer.safetensors 2617401920 &
pids+=("$!")
download_asset diffusion_models/MelBandRoformer_fp16.safetensors https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/7dc5fa7824f1f3089a5c4b130d767004ccc1ed12/MelBandRoformer_fp16.safetensors 456479072 &
pids+=("$!")

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done
if [[ "$failed" -ne 0 ]]; then
  log "one or more model downloads failed"
  exit 1
fi

curl -fsSL "$BUNDLE_BASE/ltx23-director-smoke-api.json" -o "$WORKSPACE_DIR/ltx23-smoke-api.json"

# Delete transient inputs, outputs, and previews promptly if the worker remains
# alive longer than the normal 60-second scale-to-zero window.
nohup bash -c '
  while sleep 15; do
    find /workspace/ComfyUI/input /workspace/ComfyUI/output /workspace/ComfyUI/temp \
      -type f -mmin +2 -delete 2>/dev/null || true
  done
' >/tmp/ltx23-reaper.log 2>&1 &

log "provisioning complete"
