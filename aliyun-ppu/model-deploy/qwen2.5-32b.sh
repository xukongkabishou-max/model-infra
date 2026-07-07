nerdctl run -it --rm \
  -v /data/nvme0/data/models:/models \
  --network=host \
  -p 8113:8113 \
  --device /dev/alixpu \
  $(for dev in /dev/alixpu_ppu[1-4]*; do echo "--device $dev"; done) \
  --device /dev/alixpu_ctl \
  --name qwen-base-test \
  --shm-size=128g \
  reg.docker.alibaba-inc.com/aisw/llm:v1.5.4-pytorch2.6.0-ubuntu24.04-cuda12.6-vllm0.9.1-py312 \
  python3 -m vllm.entrypoints.api_server \
    --model /models/Qwen2.5-32B-Instruct \
    --served-model-name base-qwen-model \
    --dtype half \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.85 \
    --port 8113