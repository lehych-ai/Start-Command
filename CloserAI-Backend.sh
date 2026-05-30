#!/bin/bash
# CloserAI GPU backend (Face/Color Swap) — AI-Dock provisioning script.
# Serves the FastAPI pod (github.com/lehych-ai/uniquifier-backend) on :8000.
#
# Runs the backend in its OWN venv with CUDA 11.8 libs (torch cu118 + pip cudnn),
# isolated from the base image's torch — so onnxruntime-gpu 1.16.3 (face swap)
# and gfpgan/basicsr work regardless of the host's CUDA version.
set -uo pipefail

WORKSPACE=${WORKSPACE:-/workspace}
APP_DIR="${WORKSPACE}/uniquifier-backend"
VENV="${WORKSPACE}/closerai-venv"
export MODELS_DIR="${WORKSPACE}/models"
export UPLOAD_DIR="${WORKSPACE}/uploads"
export OUTPUT_DIR="${WORKSPACE}/outputs"
PORT="${CLOSERAI_PORT:-8000}"
REPO="https://github.com/lehych-ai/uniquifier-backend"

mkdir -p "$MODELS_DIR" "$UPLOAD_DIR" "$OUTPUT_DIR"

echo "=== apt deps ==="
(sudo apt-get update -y || apt-get update -y) || true
(sudo apt-get install -y ffmpeg git wget libgl1 libglib2.0-0 \
  || apt-get install -y ffmpeg git wget libgl1 libglib2.0-0) || true

echo "=== code ==="
if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only || true
else
  git clone --depth 1 "${REPO}" "${APP_DIR}"
fi

echo "=== isolated venv (cu118) ==="
python3 -m venv "${VENV}"
source "${VENV}/bin/activate"
pip install --upgrade pip wheel

# torch cu118 first → onnxruntime-gpu 1.16.3 + gfpgan/basicsr line up
pip install --no-cache-dir torch==2.0.1 torchvision==0.15.2 --index-url https://download.pytorch.org/whl/cu118
# CUDA 11.8 runtime libs via pip so onnxruntime finds them on any host
pip install --no-cache-dir nvidia-cudnn-cu11==8.7.0.84 nvidia-cublas-cu11==11.11.3.6

# pin torch so requirements deps (xformers etc.) can't upgrade it
printf 'torch==2.0.1\ntorchvision==0.15.2\n' > /tmp/closerai-constraints.txt
pip install --no-cache-dir -r "${APP_DIR}/requirements.txt" -c /tmp/closerai-constraints.txt

echo "=== weights ==="
dl() { [[ -f "$2" ]] || wget -q --show-progress -O "$2" "$1"; }
dl "https://huggingface.co/ezioruan/inswapper_128.onnx/resolve/main/inswapper_128.onnx" "${MODELS_DIR}/inswapper_128.onnx"
dl "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth"          "${MODELS_DIR}/GFPGANv1.4.pth"
python - <<'PY' || true
from rembg import new_session
new_session("u2net"); new_session("u2net_cloth_seg")
print("rembg models cached")
PY

echo "=== LD_LIBRARY_PATH so onnxruntime sees CUDA 11.8 ==="
TORCH_LIB="$(python -c 'import torch,os;print(os.path.join(os.path.dirname(torch.__file__),"lib"))')"
CUDNN_LIB="$(python -c 'import nvidia.cudnn,os;print(os.path.join(os.path.dirname(nvidia.cudnn.__file__),"lib"))' 2>/dev/null || true)"
CUBLAS_LIB="$(python -c 'import nvidia.cublas,os;print(os.path.join(os.path.dirname(nvidia.cublas.__file__),"lib"))' 2>/dev/null || true)"
export LD_LIBRARY_PATH="${CUDNN_LIB}:${CUBLAS_LIB}:${TORCH_LIB}:${LD_LIBRARY_PATH:-}"

echo "=== launch API on :${PORT} ==="
cd "${APP_DIR}"
pkill -f "uvicorn main:app" 2>/dev/null || true
LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" \
MODELS_DIR="${MODELS_DIR}" UPLOAD_DIR="${UPLOAD_DIR}" OUTPUT_DIR="${OUTPUT_DIR}" \
API_TOKEN="${API_TOKEN:-}" \
  nohup "${VENV}/bin/uvicorn" main:app --host 0.0.0.0 --port "${PORT}" > /var/log/closerai.log 2>&1 &
disown
echo "=== CloserAI backend up on :${PORT} (log: /var/log/closerai.log) ==="
