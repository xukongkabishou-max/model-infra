#!/bin/bash

cd /opt/projects

source /root/.bashrc
export LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64/driver:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64/common:$LD_LIBRARY_PATH
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /usr/local/Ascend/nnal/atb/set_env.sh
source /usr/local/Ascend/mindie/set_env.sh
source /usr/local/Ascend/llm_model/set_env.sh
export XINFERENCE_PROMETHEUS_SRC=/opt/projects/prometheus

echo "###########################################################################"
npu-smi info
echo "###########################################################################"

echo "###########################################################################"
echo "start model background"
nohup /bin/bash -x /app/launch-model.sh &> /launch-model.log &
echo "###########################################################################"


sed -i '/listen/s/8000/8002/' /usr/local/nginx/conf/nginx.conf


echo "###########################################################################"
cat  /usr/local/nginx/conf/nginx.conf | grep -i listen
echo "###########################################################################"

./xinf-enterprise.sh --host 172.30.0.161 --port 9997 && 
    XINFERENCE_MODEL_SRC=modelscope xinference-local --host 172.30.0.161 --port 9997 --log-level debug