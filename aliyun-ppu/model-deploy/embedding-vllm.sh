nerdctl run -d \
  -v /data/nvme0/zhizixiyuan/xinference/embedding:/data/embedding \
  --device /dev/alixpu \
  $(for dev in /dev/alixpu_ppu[1-2]*; do echo "--device $dev"; done) \
  --device /dev/alixpu_ctl \
  --name vllm-embedding \
  --network=host \
  --shm-size=4g \
  asllm:1.3.1-pytorch2.6.0-ubuntu24.04-cuda12.6-vllm0.8.3-sglang0.4.6.post1-py312 \
  vllm serve /data/embedding/bce-embedding-base_v1 \
    --served-model-name bce-embedding-base \
    --host 0.0.0.0 \
    --port 9997 \
    --trust-remote-code \
    --enable-prefix-caching