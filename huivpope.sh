#!/bin/bash
set -uo pipefail

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
SERVICES_REPO="/tmp/comfy-services"

echo "=== ComfyUI запуск ==="

APT_PACKAGES=(
    git-lfs
)

PIP_PACKAGES=()

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/lehych-sol/Zen-Face-Detail"
    "https://github.com/lehych-sol/Camera-Forensic-Realism"
    "https://github.com/lehych-sol/Custom-Nodes-by-lehych"
    "https://github.com/kijai/ComfyUI-PromptRelay"
    "https://github.com/Saganaki22/ComfyUI-FishAudioS2"
    "https://github.com/MONKEYFOREVER2/comfyui-quantum-spectral-nodes"
    "https://github.com/lehych-sol/advanced-denoiser"
    "https://github.com/lehych-sol/Stolen-Nodes"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    "https://github.com/darkamenosa/comfy_nanobanana"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/donkbeef/flashVSRnode"
    "https://github.com/lehych-sol/geek-nodes"
    "https://github.com/lehych-sol/custom-nodes"
    "https://github.com/Lightricks/ComfyUI-LTXVideo"
    "https://github.com/PGCRT/CRT-Nodes CRT-Nodes-PGCRT"
    "https://github.com/Jasonzzt/ComfyUI-CacheDiT"
    "https://github.com/thatboymentor/ofmtechclip"
    "https://github.com/scraed/LanPaint"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/facok/comfyui-meancache-z"
    "https://github.com/teskor-hub/comfyui-teskors-utils"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/ClownsharkBatwing/RES4LYF"
    "https://github.com/chrisgoringe/cg-use-everywhere"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    "https://github.com/TheLustriVA/ComfyUI-Image-Size-Tools"
    "https://github.com/ZhiHui6/zhihui_nodes_comfyui"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/crystian/ComfyUI-Crystools"
    "https://github.com/plugcrypt/CRT-Nodes CRT-Nodes-plugcrypt"
    "https://github.com/EllangoK/ComfyUI-post-processing-nodes"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    "https://github.com/GACLove/ComfyUI-VFI"
    "https://github.com/ShmuelRonen/ComfyUI-FishSpeech"
)

function provisioning_start() {
    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}/.git" ]]; then
        rm -rf "${COMFYUI_DIR}"
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi

    cd "${COMFYUI_DIR}"
    git fetch origin
    git reset --hard origin/master
    pip install --no-cache-dir -r requirements.txt
}

function provisioning_install_base_reqs() {
    cd "${COMFYUI_DIR}"
    if [[ -f requirements.txt ]]; then
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        sudo apt-get update
        sudo apt-get install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for entry in "${NODES[@]}"; do
        repo="${entry%% *}"
        custom_dir="${entry#* }"
        if [[ "${custom_dir}" == "${repo}" ]]; then
            custom_dir="${repo##*/}"
        fi

        path="./${custom_dir}"
        if [[ -d "${path}/.git" ]]; then
            (cd "${path}" && git pull --ff-only) || echo "WARN: не удалось обновить ${custom_dir}, пропускаю"
        else
            git clone --recursive "${repo}" "${path}"
        fi

        if [[ -f "${path}/requirements.txt" ]]; then
            pip install --no-cache-dir -r "${path}/requirements.txt" || echo "WARN: requirements failed for ${custom_dir}, продолжаю"
        fi
    done
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

if [[ ! -f "${COMFYUI_DIR}/main.py" ]]; then
    echo "ERROR: ComfyUI не установлен: ${COMFYUI_DIR}/main.py не найден"
    exit 1
fi

echo "=== Устанавливаем зависимости сервисов ==="
pip install --no-cache-dir fastapi uvicorn requests huggingface_hub aiofiles python-multipart

echo "=== Клонируем сервисы ==="
if [[ -d "${SERVICES_REPO}/.git" ]]; then
    git -C "${SERVICES_REPO}" pull --ff-only || {
        rm -rf "${SERVICES_REPO}"
        git clone https://github.com/lehych-ai/Comfy-Services.git "${SERVICES_REPO}"
    }
else
    rm -rf "${SERVICES_REPO}"
    git clone https://github.com/lehych-ai/Comfy-Services.git "${SERVICES_REPO}"
fi

rm -rf "${WORKSPACE}/services"
cp -r "${SERVICES_REPO}/services" "${WORKSPACE}/services"

echo "=== Запускаем загрузчик пресетов (порт 8081) ==="
cd "${WORKSPACE}"
nohup /venv/main/bin/uvicorn services.preset_downloader:app --host 0.0.0.0 --port 8081 > /var/log/preset_downloader.log 2>&1 &
disown

echo "=== Запускаем ComfyUI (порт 8188) ==="
cd "${COMFYUI_DIR}"
nohup /venv/main/bin/python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /var/log/comfyui.log 2>&1 &
disown

echo "=== Снимаем блокировку provisioning для ComfyUI ==="
sudo rm -f /.provisioning 2>/dev/null || rm -f /.provisioning 2>/dev/null || true

echo "=== Provisioning завершён, ComfyUI запустится автоматически ==="
