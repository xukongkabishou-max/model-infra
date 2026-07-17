# model = /data/model/DeepSeek-V4-Flash-w8a8-mtp
# image = m.daocloud.io/docker.io/ascendai/vllm-ascend:deepseekv4

#先进入容器
docker run \
  # 分配伪终端并保持标准输入打开，方便之后进入容器交互
  -it \
  
  # 让容器在后台运行
  -d \
  
  # 设置容器名称，后续可通过 docker logs/exec/stop 使用这个名称操作
  --name vllm-ascend-ds \
  
  # 共享宿主机网络栈；容器监听 7000，就等于宿主机直接监听 7000
  --net=host \
  
  # 设置容器 /dev/shm 的最大容量，供多进程通信、权重加载和共享内存使用
  # 512g 是容量上限，不会在容器启动时立即占满 512 GB
  --shm-size=512g \
  
  # 赋予容器较高的宿主机权限，昇腾驱动、设备及部分系统操作需要
  # 安全权限很大，只应运行可信镜像
  --privileged \
  
  # 将第 0 张昇腾 NPU 映射到容器
  --device /dev/davinci0 \
  
  # 将第 1 张昇腾 NPU 映射到容器
  --device /dev/davinci1 \
  
  # 将第 2 张昇腾 NPU 映射到容器
  --device /dev/davinci2 \
  
  # 将第 3 张昇腾 NPU 映射到容器
  --device /dev/davinci3 \
  
  # 将第 4 张昇腾 NPU 映射到容器
  --device /dev/davinci4 \
  
  # 将第 5 张昇腾 NPU 映射到容器
  --device /dev/davinci5 \
  
  # 将第 6 张昇腾 NPU 映射到容器
  --device /dev/davinci6 \
  
  # 将第 7 张昇腾 NPU 映射到容器
  --device /dev/davinci7 \
  
  # 映射昇腾设备管理接口，运行时通过它查询和控制 NPU
  --device /dev/davinci_manager \
  
  # 映射设备虚拟内存管理接口，用于主机内存与 NPU 内存映射
  --device /dev/devmm_svm \
  
  # 映射 Host Device Communication 接口，用于主机与昇腾设备通信
  --device /dev/hisi_hdc \
  
  # 挂载 DCMI 管理库，供容器查询 NPU 状态、温度、功耗和健康信息
  -v /usr/local/dcmi:/usr/local/dcmi \
  
  # 挂载宿主机的 hccn_tool，用于检查和配置昇腾通信网络
  -v /usr/local/Ascend/driver/tools/hccn_tool:/usr/local/Ascend/driver/tools/hccn_tool \
  
  # 挂载宿主机 npu-smi，使容器内可以执行 NPU 状态查询
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  
  # 挂载宿主机驱动动态库
  # 容器内 CANN 最终通过这些库调用宿主机实际安装的昇腾驱动
  -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64 \
  
  # 挂载驱动版本文件，供 CANN 和框架检查驱动版本及兼容性
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  
  # 挂载昇腾安装信息，包括驱动安装目录、用户和安装状态
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  
  # 挂载 HCCN 通信配置；多卡 HCCL 通信需要读取设备 IP 和通信信息
  -v /etc/hccn.conf:/etc/hccn.conf \
  
  # 把宿主机模型目录挂载为容器内的 /models
  # :ro 表示只读，防止容器误删或修改 280 GB 权重
  -v /data/model/DeepSeek-V4-Flash-w8a8-mtp:/models:ro \
  
  # 使用本机已经加载好的 ARM64 vLLM Ascend DeepSeek-V4 镜像
  m.daocloud.io/docker.io/ascendai/vllm-ascend:deepseekv4 \
  
  # 容器启动后运行 Bash；因为同时使用了 -it -d，Bash 会在后台保持运行
  bash

  #再启动模型
export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=8
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export ACL_OP_INIT_MODE=1
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
export USE_MULTI_GROUPS_KV_CACHE=1
export TASK_QUEUE_ENABLE=1
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_BUFFSIZE=512
export USE_MULTI_BLOCK_POOL=1


# export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD  # 预加载 jemalloc，改善多线程内存分配性能，减少碎片和锁竞争

# export OMP_PROC_BIND=false  # 不强制把 OpenMP 线程固定在特定 CPU 核上，避免与 vLLM 自己的 CPU 绑核策略冲突

# export OMP_NUM_THREADS=8  # 每个 OpenMP 计算任务最多使用 8 个 CPU 线程；不是整个服务只能使用 8 核

# export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True  # 允许 PyTorch NPU 显存段动态扩展，减少显存碎片和因连续大块不足导致的 OOM

# export ACL_OP_INIT_MODE=1  # 启用 ACL 算子初始化优化模式，减少部分算子首次执行时的初始化开销；属于昇腾运行时开关

# export VLLM_ASCEND_ENABLE_FLASHCOMM1=1  # 开启 FlashComm1 通信优化，降低 TP 场景中 NPU 间通信与计算开销

# export USE_MULTI_GROUPS_KV_CACHE=1  # 启用多组 KV Cache 支持，适配 DeepSeek-V4 的混合注意力及不同 KV Cache 组织方式

# export TASK_QUEUE_ENABLE=1  # 启用昇腾异步任务队列，让 CPU 下发任务与 NPU 执行尽量重叠

# export HCCL_OP_EXPANSION_MODE=AIV  # 让部分 HCCL 通信算子使用 AI Vector Core 展开执行，优化卡间通信

# export HCCL_BUFFSIZE=512  # HCCL 通信缓冲区大小，单位通常为 MB；值越大越可能提升大规模通信，但会多占用每卡显存

# export USE_MULTI_BLOCK_POOL=1  # 启用多个 KV Cache Block Pool，配合多组 KV Cache 管理；属于模型适配内部开关，不建议随意关闭

vllm serve /models \
  --safetensors-load-strategy prefetch \
  --max-model-len 133120 \
  --enable-prefix-caching \
  --max-num-batched-tokens 4096 \
  --served-model-name ds \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 16 \
  --data-parallel-size 1 \
  --tensor-parallel-size 8 \
  --enable-expert-parallel \
  --quantization ascend \
  --port 7000 \
  --block-size 128 \
  --enable-chunked-prefill \
  --tokenizer-mode deepseek_v4 \
  --tool-call-parser deepseek_v4 \
  --enable-auto-tool-choice \
  --reasoning-parser deepseek_v4 \
  --async-scheduling \
  --additional-config '{"enable_cpu_binding":true,"multistream_overlap_shared_expert":false}' \
  --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}' \
  --model-loader-extra-config '{"enable_multithread_load":true,"num_threads":16}' \
  --speculative-config '{"num_speculative_tokens":1,"method":"mtp"}'


# VLLM_ARGS=(
#   --safetensors-load-strategy prefetch
#   # 预取 safetensors 权重，提高模型加载速度；会使用更多宿主机内存和文件缓存

#   --max-model-len 133120
#   # 单个请求允许的最大上下文长度，即输入 Token + 输出 Token 的总上限

#   --max-num-batched-tokens 4096
#   # 每个调度迭代最多处理的 Token 数；调高可增加吞吐，但会增加显存使用和单请求延迟波动

#   --served-model-name ds
#   # 对外暴露的模型名称；API 请求中的 "model" 必须填写 "ds"

#   --gpu-memory-utilization 0.90
#   # vLLM 可使用的单卡 NPU 显存比例上限；虽然参数名是 gpu，在昇腾上表示 NPU 显存

#   --max-num-seqs 16
#   # 同一调度周期最多同时处理 16 条序列；限制并发上限和 KV Cache 压力

#   --data-parallel-size 1
#   # 数据并行规模为 1，不复制第二套模型实例；当前 8 卡共同服务一套模型

#   --tensor-parallel-size 8
#   # 将模型张量切分到 8 张 NPU，正好使用当前节点的全部 8 卡

#   --enable-expert-parallel
#   # 对 MoE 专家层启用专家并行，让不同专家分布在不同 NPU 上执行

#   --quantization ascend
#   # 使用 vLLM Ascend 的量化加载和计算后端，匹配当前 W8A8 权重

#   --port 7000
#   # OpenAI 兼容 API 服务监听端口；请求地址应使用 http://节点地址:7000

#   --block-size 128
#   # KV Cache 每个内存块容纳 128 个 Token；影响 KV Cache 分配粒度、碎片和调度效率

#   --enable-chunked-prefill
#   # 将很长的输入拆成多个块执行 Prefill，避免单个长请求一次占满调度预算

#   --tokenizer-mode deepseek_v4
#   # 使用 DeepSeek-V4 专用 Tokenizer 处理模式

#   --tool-call-parser deepseek_v4
#   # 使用 DeepSeek-V4 专用工具调用解析器，把输出转换为 OpenAI 风格 tool_calls

#   --enable-auto-tool-choice
#   # 允许模型自动决定是否调用工具，而不要求客户端强制指定某个工具

#   --reasoning-parser deepseek_v4
#   # 使用 DeepSeek-V4 专用推理内容解析器，区分 reasoning 与最终回答

#   --async-scheduling
#   # 启用异步调度，使请求调度、CPU 处理和 NPU 计算尽量重叠，提高吞吐

#   --additional-config '{"enable_cpu_binding":true,"multistream_overlap_shared_expert":false}'
#   # enable_cpu_binding=true：将工作进程合理绑定到 NUMA/CPU 核，减少跨 NUMA 访问
#   # multistream_overlap_shared_expert=false：不让共享专家计算通过多 Stream 与其他计算重叠，稳定优先

#   --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}'
#   # 仅在 Decode 阶段捕获并复用 ACL Graph，减少逐 Token 生成时的算子下发开销

#   --model-loader-extra-config '{"enable_multithread_load":true,"num_threads":16}'
#   # 使用 16 个线程并行读取和加载 70 个权重分片，加快启动速度；基本不影响运行期推理

#   --speculative-config '{"num_speculative_tokens":1,"method":"mtp"}'
#   # 开启 MTP 推测解码，每轮额外预测 1 个 Token；预测被验证接受后可减少解码次数
# )