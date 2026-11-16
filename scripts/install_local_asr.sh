#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/Library/Python/3.14/bin:${HOME}/Library/Python/3.13/bin:${HOME}/Library/Python/3.12/bin:${HOME}/Library/Python/3.11/bin:${HOME}/Library/Python/3.10/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
MODELS_DIR="${HOME}/Library/Application Support/SimulTrans/Models"
WHISPER_DIR="${HOME}/vscode/whisper.cpp"
WHISPER_MODEL_DIR="${MODELS_DIR}/whisper"
QWEN_CACHE_DIR="${MODELS_DIR}/qwen/huggingface"
WHISPER_MODEL_NAME="${WHISPER_MODEL_NAME:-large-v3-turbo}"
QWEN_PYTHON="${QWEN_PYTHON:-python3}"

install_whisper_cpp() {
    if [[ ! -d "${WHISPER_DIR}/.git" ]]; then
        git clone https://github.com/ggml-org/whisper.cpp.git "${WHISPER_DIR}"
    fi

    cmake -B "${WHISPER_DIR}/build" -S "${WHISPER_DIR}" -DGGML_METAL=ON
    cmake --build "${WHISPER_DIR}/build" -j --config Release

    mkdir -p "${WHISPER_MODEL_DIR}"
    "${WHISPER_DIR}/models/download-ggml-model.sh" "${WHISPER_MODEL_NAME}" "${WHISPER_MODEL_DIR}"

    echo "Whisper server:"
    echo "  ${WHISPER_DIR}/build/bin/whisper-server"
    echo "Whisper model:"
    find "${WHISPER_MODEL_DIR}" -maxdepth 1 -name '*large-v3-turbo*.bin' -print
}

install_qwen_mlx() {
    mkdir -p "${QWEN_CACHE_DIR}"
    export HF_HOME="${QWEN_CACHE_DIR}"
    export HF_HUB_CACHE="${QWEN_CACHE_DIR}/hub"

    "${QWEN_PYTHON}" -m pip install --upgrade pip
    "${QWEN_PYTHON}" -m pip install --upgrade "mlx-qwen3-asr[aligner,serve]"

    echo "Warming Qwen3-ASR-1.7B cache. The first run downloads model weights."
    "${QWEN_PYTHON}" - <<'PY'
from mlx_qwen3_asr import Session
session = Session(model="Qwen/Qwen3-ASR-1.7B")
print(session.model_info)
PY
}

print_next_steps() {
    cat <<EOF

Local ASR setup finished.

SimulTrans looks for:
  Whisper server: ${WHISPER_DIR}/build/bin/whisper-server
  Whisper model:  ${WHISPER_MODEL_DIR}/ggml-large-v3-turbo*.bin
  Qwen cache:     ${QWEN_CACHE_DIR}
  Qwen sidecar:   ${ROOT_DIR}/scripts/qwen3_asr_server.py
  Qwen Python:    ${QWEN_PYTHON} with mlx-qwen3-asr installed

If you use custom paths, launch SimulTrans with:
  SIMULTRANS_WHISPER_SERVER=/path/to/whisper-server \\
  SIMULTRANS_WHISPER_MODEL=/path/to/ggml-large-v3-turbo.bin \\
  SIMULTRANS_QWEN3_ASR_PYTHON=/path/to/python3 \\
  SIMULTRANS_QWEN3_ASR_SIDECAR=/path/to/qwen3_asr_server.py \\
  ./build_and_run.sh

EOF
}

case "${1:-all}" in
    all)
        install_whisper_cpp
        install_qwen_mlx
        print_next_steps
        ;;
    whisper)
        install_whisper_cpp
        print_next_steps
        ;;
    qwen)
        install_qwen_mlx
        print_next_steps
        ;;
    *)
        echo "Usage: ${ROOT_DIR}/scripts/install_local_asr.sh [all|whisper|qwen]" >&2
        exit 2
        ;;
esac
