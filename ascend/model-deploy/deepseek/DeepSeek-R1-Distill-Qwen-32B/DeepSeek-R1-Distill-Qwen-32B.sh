#!/bin/bash

set -eux

replicas=1


cat > app-start.sh <<"EOF"
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
cp /app/config.json /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
chmod 640 /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
ls -l conf
# chmod o-r conf/config.json
echo "================================================================================================================"
echo "Begin start"
echo "================================================================================================================"
./bin/mindieservice_daemon
EOF



# cat > app-start.sh <<"EOF"
# #!/bin/bash
# set -x

# # 加载显卡相关变量
# source /root/.bashrc
# export LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64/driver:$LD_LIBRARY_PATH
# export LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64/common:$LD_LIBRARY_PATH
# export LANG=en_US.UTF-8
# export LANGUAGE=en_US:en
# export LC_ALL=en_US.UTF-8
# source /usr/local/Ascend/ascend-toolkit/set_env.sh
# source /usr/local/Ascend/nnrt/set_env.sh
# source /usr/local/Ascend/nnae/set_env.sh
# source /usr/local/Ascend/driver/bin/setenv.bash

# echo "================================================================================================================"
# npu-smi info
# echo "================================================================================================================"

# cd /usr/local/Ascend/mindie/latest/mindie-service
# ls -l conf
# cp /app/config.json /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
# chmod 640 /usr/local/Ascend/mindie/latest/mindie-service/conf/config.json
# ls -l conf
# chmod o-r conf/config.json
# echo "================================================================================================================"
# echo "Begin start"
# echo "================================================================================================================"
# ./bin/mindieservice_daemon
# EOF



docker rm -f mindie-ds-model-1
sleep 5
    #--privileged \
docker run -it -d --net=host --shm-size=1g \
    --name mindie-ds-model-1 \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --device=/dev/davinci4 \
    --device=/dev/davinci5 \
    --restart=always \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
    -v /usr/local/sbin:/usr/local/sbin:ro \
    -v /root/data/model:/root/data/model:ro \
    -v $(pwd)/conf/mindie-deepseek-config-1.json:/app/config.json \
    -v $(pwd)/app-start.sh:/app/start.sh \
    swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:1.0.RC3-800I-A2-arm64 bash /app/start.sh
    # swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:2.0.T3.1-800I-A2-py311-openeuler24.03-lts bash
    # swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:1.0.RC3-800I-A2-arm64 bash /app/start.sh


docker ps -a | grep "mindie-ds-model"

docker logs -f mindie-ds-model-1