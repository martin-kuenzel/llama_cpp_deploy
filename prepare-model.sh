#!/bin/bash
set -e

# Configuration
HF_REPO=${1:-"Qwen/Qwen3.6-35B-A3B"}
TARGET_QUANT=${2:-"Q4_K_M"}

# Extract model name from repo (e.g., Qwen/Qwen3.6-35B-A3B -> Qwen3.6-35B-A3B)
MODEL_BASENAME=$(basename "$HF_REPO")
MODEL_FP16="${MODEL_BASENAME}-fp16.gguf"
MODEL_QUANTIZED="${MODEL_BASENAME}-${TARGET_QUANT}.gguf"

echo "=== System Preparation ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y git git-lfs build-essential cmake

echo "=== Downloading Model ==="
if ! command -v hf &> /dev/null; then
    echo "hf cli could not be found. Installing via pip..."
    pip install -U "huggingface_hub[cli]"
fi

# Download from HF
hf download "${HF_REPO}" --local-dir "./${MODEL_BASENAME}" --local-dir-use-symlinks False

echo "=== Cloning and Building llama.cpp === "
if [ ! -d "llama.cpp" ]; then
    git clone https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp

# Prepare python env
echo "=== Setting up Python environment ==="
pip install -r requirements.txt

echo "=== Converting Model to GGUF (FP16) ==="
python convert_hf_to_gguf.py "../${MODEL_BASENAME}" --outfile "../${MODEL_FP16}" --outtype f16

echo "=== Building llama-quantize ==="
mkdir -p build
cd build
cmake ..
cmake --build . --config Release -j $(nproc) --target llama-quantize

echo "=== Quantizing Model to ${TARGET_QUANT} ==="
./bin/llama-quantize "../../${MODEL_FP16}" "../../${MODEL_QUANTIZED}" "${TARGET_QUANT}"

cd ../../

echo "=== Cleanup ==="
echo "Removing the unquantized raw weights to save space..."
rm -rf "./${MODEL_BASENAME}"

# Fix file permissions because Docker creates them as root
chown -R $(stat -c "%u:%g" ./) ./ || true

echo ""
echo "Done! The quantized model has been created: ./$MODEL_QUANTIZED"
echo "You can update the .env file with MODEL_NAME=$MODEL_QUANTIZED"
