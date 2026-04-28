#!/bin/bash
set -e

# Configuration
HF_REPO=${1:-"Qwen/Qwen3.6-35B-A3B"}
TARGET_QUANT=${2:-"Q4_K_M"}

# Extract model name from repo (e.g., Qwen/Qwen3.6-35B-A3B -> Qwen3.6-35B-A3B)
MODEL_BASENAME=$(basename "$HF_REPO")
MODEL_FP16="${MODEL_BASENAME}-fp16.gguf"
MODEL_QUANTIZED="${MODEL_BASENAME}-${TARGET_QUANT}.gguf"
SUCCESS=0
WORKSPACE="/workspace"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
step_done() {
    # Check whether a step has been completed in a previous run
    [ -f "${WORKSPACE}/.step_${1}_done" ]
}

mark_done() {
    # Mark a step as completed
    touch "${WORKSPACE}/.step_${1}_done"
}

ask_yes_no() {
    # Ask user a yes/no question. Default answer given as $2 (y/n).
    local prompt="$1"
    local default="${2:-y}"
    local answer

    if [ "$default" = "y" ]; then
        prompt="${prompt} [Y/n] "
    else
        prompt="${prompt} [y/N] "
    fi

    read -r -p "$prompt" answer </dev/tty
    answer="${answer:-$default}"
    case "$answer" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Cleanup (only on failure / interrupt)
# ---------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    echo ""
    echo "=== Cleanup ==="

    if [ $exit_code -ne 0 ] || [ $SUCCESS -eq 0 ]; then
        echo "Script interrupted or failed. Cleaning up incomplete files..."
        # Only remove artifacts whose step is NOT marked done
        if ! step_done "download"; then
            rm -rf "${WORKSPACE}/${MODEL_BASENAME}"
        fi
        if ! step_done "convert"; then
            rm -f "${WORKSPACE}/${MODEL_FP16}"
        fi
        if ! step_done "quantize"; then
            rm -f "${WORKSPACE}/${MODEL_QUANTIZED}"
        fi
    fi

    # Fix file permissions because Docker creates them as root
    chown -R $(stat -c "%u:%g" ${WORKSPACE}/) ${WORKSPACE}/ || true

    exit $exit_code
}

trap cleanup EXIT INT TERM

cd "${WORKSPACE}"

# ===========================================================================
# Step 0 – System Preparation (always run to ensure tools are available)
# ===========================================================================
echo "=== System Preparation ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y git git-lfs build-essential cmake

# ===========================================================================
# Step 1 – Download Model
# ===========================================================================
if step_done "download"; then
    echo ""
    echo "=== Skipping download – model weights already present ==="
else
    echo ""
    echo "=== Downloading Model ==="
    if ! command -v hf &> /dev/null; then
        echo "hf cli could not be found. Installing via pip..."
        pip install -U "huggingface_hub[cli]"
    fi

    hf download "${HF_REPO}" --local-dir "./${MODEL_BASENAME}"
    mark_done "download"
fi

# ===========================================================================
# Step 2 – Clone / build llama.cpp + convert to FP16 GGUF
# ===========================================================================
if step_done "convert"; then
    echo ""
    echo "=== Skipping conversion – FP16 GGUF already exists ==="
else
    echo ""
    echo "=== Cloning and Building llama.cpp ==="
    if [ ! -d "llama.cpp" ]; then
        git clone https://github.com/ggerganov/llama.cpp.git
    fi
    cd llama.cpp

    echo "=== Setting up Python environment ==="
    pip install -r requirements.txt

    echo "=== Converting Model to GGUF (FP16) ==="
    python convert_hf_to_gguf.py "../${MODEL_BASENAME}" --outfile "../${MODEL_FP16}" --outtype f16

    cd ..
    mark_done "convert"
fi

# ===========================================================================
# Step 3 – Quantize
# ===========================================================================
if step_done "quantize"; then
    echo ""
    echo "=== Skipping quantization – quantized GGUF already exists ==="
else
    echo ""
    echo "=== Building llama-quantize ==="
    # Make sure llama.cpp is available (it should be from Step 2)
    if [ ! -d "llama.cpp" ]; then
        git clone https://github.com/ggerganov/llama.cpp.git
    fi
    cd llama.cpp
    mkdir -p build
    cd build
    cmake ..
    cmake --build . --config Release -j $(nproc) --target llama-quantize

    echo "=== Quantizing Model to ${TARGET_QUANT} ==="
    ./bin/llama-quantize "../../${MODEL_FP16}" "../../${MODEL_QUANTIZED}" "${TARGET_QUANT}"

    cd ../../
    mark_done "quantize"
fi

SUCCESS=1

# ===========================================================================
# Post-processing – optional cleanup of intermediate artifacts
# ===========================================================================
echo ""
echo "============================================="
echo "  Done! Quantized model created:"
echo "  ./${MODEL_QUANTIZED}"
echo "============================================="
echo ""

# --- Ask whether to delete the downloaded (raw) model weights ---------------
if [ -d "${WORKSPACE}/${MODEL_BASENAME}" ]; then
    echo "The downloaded HuggingFace model weights are still present:"
    echo "  ${WORKSPACE}/${MODEL_BASENAME}"
    du -sh "${WORKSPACE}/${MODEL_BASENAME}" 2>/dev/null || true
    echo ""
    if ask_yes_no "Delete the downloaded model weights to free disk space?" "y"; then
        echo "Removing downloaded model weights..."
        rm -rf "${WORKSPACE}/${MODEL_BASENAME}"
        # Clear the download marker so a future run will re-download if needed
        rm -f "${WORKSPACE}/.step_download_done"
        echo "Deleted."
    else
        echo "Keeping downloaded model weights."
    fi
fi

# --- Ask whether to delete the intermediate FP16 GGUF ----------------------
if [ -f "${WORKSPACE}/${MODEL_FP16}" ]; then
    echo ""
    echo "The intermediate FP16 GGUF is still present:"
    echo "  ${WORKSPACE}/${MODEL_FP16}"
    du -sh "${WORKSPACE}/${MODEL_FP16}" 2>/dev/null || true
    echo ""
    if ask_yes_no "Delete the FP16 GGUF to free disk space?" "y"; then
        echo "Removing FP16 GGUF..."
        rm -f "${WORKSPACE}/${MODEL_FP16}"
        # Clear the convert marker so a future run will reconvert if needed
        rm -f "${WORKSPACE}/.step_convert_done"
        echo "Deleted."
    else
        echo "Keeping FP16 GGUF."
    fi
fi

echo ""
echo "You can update the .env file with MODEL_NAME=$MODEL_QUANTIZED"
