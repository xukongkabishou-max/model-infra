nerdctl run -d \
  -v /data/embedding:/data/embedding \
  --device /dev/alixpu \
  --device /dev/alixpu_ppu5 \
  --device /dev/alixpu_ctl \
  --name vllm-rerank \
  --network=host \
  --shm-size=4g \
  asllm:1.3.1-pytorch2.6.0-ubuntu24.04-cuda12.6-vllm0.8.3-sglang0.4.6.post1-py312 \
  vllm serve /data/embedding/bce-reranker-base_v1 \
    --served-model-name	bce-reranker-base \
    --host 0.0.0.0 \
    --port 9998 \
    --trust-remote-code \
    --enable-prefix-caching