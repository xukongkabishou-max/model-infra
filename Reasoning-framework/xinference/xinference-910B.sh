#!/bin/bash

docker rm -f xinference-qwen32b-0329
    #--privileged=true \
docker run --name xinference-qwen32b-0329 -itd \
    --net=host \
    --restart=always \
    --shm-size=500g \
    -w /opt/projects \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --device=/dev/davinci0 \
    --device=/dev/davinci1 \
    --entrypoint=bash \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /data/zhangjiacong/LLamaFactory/lora/lora_32B:/data/zhangjiacong/LLamaFactory/lora/lora_32B \
    -v /data/model/sop_stf:/data/model/sop_stf \
    -v /data:/data \
    -v /home:/home \
    -v /root:/root/model \
    -v /tmp:/tmp \
    -v $(pwd):/app \
    harbor.ecmasai.com/xinference/xinference-prod:0.0.10-910b \
    -x /app/start.sh


echo "=========================================================================="
#docker logs -f xinference-qwen32b-0329