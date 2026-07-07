#!/bin/bash
set -ex

# 加载显卡相关变量
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

echo "================================================================================================================"
npu-smi info
echo "================================================================================================================"

cd /usr/local/Ascend/mindie/latest/mindie-service
ls -l conf
cp /ascend-start-config.json /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
chmod 440 /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
ls -l conf
# chmod o-r conf/config.json
echo "================================================================================================================"
echo "Begin start"
echo "================================================================================================================"
./bin/mindieservice_daemon