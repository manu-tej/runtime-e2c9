#!/usr/bin/env bash
set -Eeuo pipefail

# Public model/runtime provisioning for the isolated SCAIL-2 worker. User
# references, driving videos, prompts, masks, histories, and outputs stay in
# ephemeral worker RAM/scratch and are never written to this bundle.

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
COMFY_DIR="${WORKSPACE_DIR}/ComfyUI"
MODEL_DIR="${COMFY_DIR}/models"
WRAPPER_DIR="/opt/comfyui-api-wrapper"
WRAPPER_REF="e1d04af1f3bbd2d44c33e0adf419d6ca57dedd88"
PYTHON_BIN="/venv/main/bin/python"
RUNTIME_BUNDLE_REF="${RUNTIME_BUNDLE_REF:?RUNTIME_BUNDLE_REF must pin the public runtime bundle}"
BUNDLE_BASE="https://raw.githubusercontent.com/manu-tej/runtime-e2c9/${RUNTIME_BUNDLE_REF}"
MODEL_LOG="${MODEL_LOG:-/var/log/portal/comfyui.log}"

mkdir -p "$(dirname "$MODEL_LOG")" "$MODEL_DIR"/{diffusion_models,checkpoints,clip_vision,text_encoders,vae,loras}

log() {
  printf '[scail2-provision] %s\n' "$*" | tee -a "$MODEL_LOG"
}

trap 'log "ERROR at line $LINENO"' ERR

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

log "pinning ComfyUI v0.29.2"
git -C "$COMFY_DIR" fetch --quiet --depth 1 origin tag v0.29.2
git -C "$COMFY_DIR" checkout --quiet --force v0.29.2
"$PYTHON_BIN" -m pip install --no-cache-dir -q -r "$COMFY_DIR/requirements.txt" av

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

log "pinning API wrapper with inline base64 output support"
if [[ -d "$WRAPPER_DIR/.git" ]]; then
  git -C "$WRAPPER_DIR" fetch --quiet --depth 1 origin "$WRAPPER_REF"
  git -C "$WRAPPER_DIR" checkout --quiet --force "$WRAPPER_REF"
else
  clone_at https://github.com/ai-dock/comfyui-api-wrapper.git "$WRAPPER_REF" "$WRAPPER_DIR"
fi
install_requirements "$WRAPPER_DIR/requirements.txt"

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
  if [[ -f "$partial" && ! -f "${partial}.aria2" ]]; then
    rm -f "$partial"
  fi
  log "downloading $relative"
  aria2c --allow-overwrite=true --auto-file-renaming=false --continue=true \
    --file-allocation=none --max-connection-per-server=16 --min-split-size=16M \
    --quiet=true --split=16 --dir="$(dirname "$destination")" \
    --out="$(basename "$partial")" "$url"
  local actual_size
  actual_size="$(stat -c %s "$partial")"
  if [[ "$actual_size" != "$expected_size" ]]; then
    log "size mismatch for $relative: $actual_size != $expected_size"
    return 1
  fi
  mv "$partial" "$destination"
}

log "installing pinned workflow nodes"
CUSTOM_NODES="$COMFY_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES"
clone_at https://github.com/kijai/ComfyUI-KJNodes.git 4d46ac107c33ed8a3d181b8776ede66498583380 "$CUSTOM_NODES/ComfyUI-KJNodes"
clone_at https://github.com/rgthree/rgthree-comfy.git 6b76ee6f2c5a007710b5a16f97c94330d6ecc871 "$CUSTOM_NODES/rgthree-comfy"
clone_at https://github.com/chrisgoringe/cg-use-everywhere.git 50ae9f8c5d8b9538589663c90a15d4067a02969c "$CUSTOM_NODES/cg-use-everywhere"
rm -rf "$CUSTOM_NODES/ComfyUI-VideoHelperSuite"
mkdir -p "$CUSTOM_NODES/ComfyUI-VideoHelperSuite" "$CUSTOM_NODES/comfy_fleet_zero"
curl -fsSL https://cdn.comfy.org/kosinkadink/comfyui-videohelpersuite/1.7.9/node.zip -o /tmp/vhs.zip
unzip -q /tmp/vhs.zip -d "$CUSTOM_NODES/ComfyUI-VideoHelperSuite"
curl -fsSL "$BUNDLE_BASE/comfy_fleet_zero.py" -o "$CUSTOM_NODES/comfy_fleet_zero/__init__.py"
install_requirements "$CUSTOM_NODES/ComfyUI-KJNodes/requirements.txt"
install_requirements "$CUSTOM_NODES/ComfyUI-VideoHelperSuite/requirements.txt"

log "downloading pinned public SCAIL-2 model pack"
download_asset diffusion_models/wan2.1_14B_SCAIL_2_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/SCAIL-2/resolve/7fe7dbf8dad000ff756227d71d8e81da0fca40fa/diffusion_models/wan2.1_14B_SCAIL_2_fp8_scaled.safetensors 17694586857 &
pids=("$!")
download_asset checkpoints/sam3.1_multiplex_fp16.safetensors https://huggingface.co/Comfy-Org/sam3.1/resolve/ba901fbc9701054c359ed5240c4d76f83a178108/checkpoints/sam3.1_multiplex_fp16.safetensors 1745546848 &
pids+=("$!")
download_asset clip_vision/clip_vision_h.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/06e001fc51048fb03433a6fb25334de7836704a5/split_files/clip_vision/clip_vision_h.safetensors 1264219396 &
pids+=("$!")
download_asset text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/06e001fc51048fb03433a6fb25334de7836704a5/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors 6735906897 &
pids+=("$!")
download_asset vae/wan_2.1_vae.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/06e001fc51048fb03433a6fb25334de7836704a5/split_files/vae/wan_2.1_vae.safetensors 253815318 &
pids+=("$!")
download_asset loras/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors https://huggingface.co/lightx2v/Wan2.1-I2V-14B-480P-StepDistill-CfgDistill-Lightx2v/resolve/fef288b326f4fed6d2983b9800c35363da31fcfe/loras/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors 739472104 &
pids+=("$!")
download_asset loras/wan2.1_SCAIL_2_DPO_lora_bf16.safetensors https://huggingface.co/Comfy-Org/SCAIL-2/resolve/7fe7dbf8dad000ff756227d71d8e81da0fca40fa/loras/wan2.1_SCAIL_2_DPO_lora_bf16.safetensors 1226936552 &
pids+=("$!")
download_asset loras/wan2.1_SCAIL_2_relight_lora_bf16.safetensors https://huggingface.co/Comfy-Org/SCAIL-2/resolve/7fe7dbf8dad000ff756227d71d8e81da0fca40fa/loras/wan2.1_SCAIL_2_relight_lora_bf16.safetensors 1226936552 &
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

curl -fsSL "$BUNDLE_BASE/scail2-vast-benchmark-api.json" -o "$WORKSPACE_DIR/scail2-benchmark-api.json"

nohup bash -c '
  while sleep 15; do
    find /workspace/ComfyUI/input /workspace/ComfyUI/output /workspace/ComfyUI/temp \
      -type f -mmin +2 -delete 2>/dev/null || true
  done
' >/tmp/scail2-reaper.log 2>&1 &

log "provisioning complete"
