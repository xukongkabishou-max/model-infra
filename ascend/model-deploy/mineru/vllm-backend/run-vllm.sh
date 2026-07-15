#!/usr/bin/env bash
set -Eeuo pipefail

docker rm -f mineru-api >/dev/null 2>&1 || true

docker run -d \
  --name mineru-api \
  --restart unless-stopped \
  --network=host \
  --ipc=host \
  --log-opt max-size=100m \
  --log-opt max-file=3 \
  --device=/dev/davinci4 \
  --device=/dev/davinci_manager \
  --device=/dev/devmm_svm \
  --device=/dev/hisi_hdc \
  -v /var/log/npu:/usr/slog \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64 \
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  -v /data/mineru/root:/root \
  -v /data/mineru/input:/data/input \
  -v /data/mineru/output:/workspace/output \
  -e MINERU_MODEL_SOURCE=local \
  -e MINERU_LMDEPLOY_DEVICE=ascend \
  -e VLLM_WORKER_MULTIPROC_METHOD=spawn \
  -e HCCL_OP_EXPANSION_MODE=AIV \
  -e TASK_QUEUE_ENABLE=1 \
  -e PYTORCH_NPU_ALLOC_CONF=expandable_segments:True \
  -e MINERU_API_MAX_CONCURRENT_REQUESTS=1 \
  -e MINERU_PROCESSING_WINDOW_SIZE=4 \
  -e MINERU_API_OUTPUT_ROOT=/workspace/output \
  -e MINERU_VLM_TEMPERATURE=0 \
  -e MINERU_VLM_TOP_P=1 \
  -e MINERU_VLM_DO_SAMPLE=false \
  -e VLLM_TEMPERATURE=0 \
  -e VLLM_TOP_P=1 \
  mineru:npu-vllm-3.4.4 \
  mineru-api \
    --host 0.0.0.0 \
    --port 8000 \
    --enable-vlm-preload true

echo "mineru-api started"
docker ps --filter name=mineru-api