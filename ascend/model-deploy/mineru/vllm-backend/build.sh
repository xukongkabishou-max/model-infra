docker build \
  --pull \
  --platform linux/arm64 \
  --network=host \
  --progress=plain \
  -t mineru:npu-vllm-3.4.4 \
  -f npu.Dockerfile \
  .