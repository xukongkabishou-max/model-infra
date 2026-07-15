# 私有化构建来源https://opendatalab.github.io/MinerU/zh/usage/

RUN chmod +x /opt/mineru-compat/start-mineru-sglang-compat.sh

EXPOSE 16543
CMD ["/opt/mineru-compat/start-mineru-sglang-compat.sh"]
[root@c500 compat]# cat start-mineru-sglang-compat.sh
#!/usr/bin/env bash
set -euo pipefail

export MINERU_MODEL_SOURCE=${MINERU_MODEL_SOURCE:-local}
export MINERU_VLLM_DEVICE=${MINERU_VLLM_DEVICE:-maca}
export VLLM_WORKER_MULTIPROC_METHOD=${VLLM_WORKER_MULTIPROC_METHOD:-spawn}
# MetaX sGPU CDI may inject physical indexes such as 2; vLLM-metax expects no visible-device remap inside the pod.
unset CUDA_VISIBLE_DEVICES MACA_VISIBLE_DEVICES
export MINERU_VLM_MODEL_PATH=${MINERU_VLM_MODEL_PATH:-/root/.cache/modelscope/hub/models/OpenDataLab/MinerU2___5-Pro-2605-1___2B}
export MINERU_SERVED_MODEL_NAME=${MINERU_SERVED_MODEL_NAME:-MinerU2.5-Pro-2605-1.2B}
export VLLM_INTERNAL_PORT=${VLLM_INTERNAL_PORT:-30000}
export MINERU_COMPAT_PORT=${MINERU_COMPAT_PORT:-16543}
export VLLM_BASE_URL=${VLLM_BASE_URL:-http://127.0.0.1:${VLLM_INTERNAL_PORT}}

/opt/conda/bin/mineru-vllm-server \
  --model "${MINERU_VLM_MODEL_PATH}" \
  --host 127.0.0.1 \
  --port "${VLLM_INTERNAL_PORT}" \
  --served-model-name "${MINERU_SERVED_MODEL_NAME}" \
  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.70}" \
  --trust-remote-code \
  ${MINERU_VLLM_EXTRA_ARGS:-} &
VLLM_PID=$!

cleanup() {
  kill "${VLLM_PID}" 2>/dev/null || true
  wait "${VLLM_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Give uvicorn a process to supervise while vLLM loads in the background.
exec /opt/conda/bin/python3 -m uvicorn mineru_sglang_compat_server:app \
  --host 0.0.0.0 \
  --port "${MINERU_COMPAT_PORT}" \
  --app-dir /opt/mineru-compat
