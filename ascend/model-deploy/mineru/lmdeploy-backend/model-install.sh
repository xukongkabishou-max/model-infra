python3 -m venv /data/mineru/root/.model-downloader

source /data/mineru/root/.model-downloader/bin/activate

python3 -m pip install -U pip \
          -i https://mirrors.aliyun.com/pypi/simple

python3 -m pip install 'mineru==3.4.4' \
          -i https://mirrors.aliyun.com/pypi/simple

export HOME=/data/mineru/root
export MINERU_MODEL_SOURCE=modelscope

mineru-models-download -s modelscope -m pipeline

mineru-models-download -s modelscope -m vlm

sed -i 's#/data/mineru/root#/root#g' \
          /data/mineru/root/mineru.json