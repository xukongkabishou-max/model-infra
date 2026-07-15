# MinerU 在 Ascend 910B 上使用 vLLM 与 lmdeploy 解析 PDF 的区别

## 1. 核心结论

vLLM 和 lmdeploy 在 MinerU 里都不是 PDF 解析器本身，它们是 MinerU 调用视觉大模型时使用的推理引擎。

PDF 解析质量的差异，主要来自它们在 Ascend 910B 上生成结构化 layout token 的稳定性不同。

本次实测结论：

| 后端 | 结果 |
|---|---|
| vLLM | 能跑通，但 layout 输出异常，出现 bbox 和格式 warning |
| lmdeploy | 能跑通，速度更快，layout 输出干净，没有 bbox 和格式 warning |

当前这台 910B3 环境更适合使用 lmdeploy 作为 MinerU 的 VLM 推理后端。

## 2. MinerU PDF 解析整体链路

MinerU 解析 PDF 大致流程如下：

```text
PDF
  -> 页面转图片
  -> 构造 VLM 提示词
  -> 推理引擎调用视觉大模型
  -> 模型输出 layout 结构
  -> MinerU 解析 layout token
  -> 生成 md / middle_json / 图片 / content_list
```

其中，推理引擎负责调用视觉大模型，让模型根据页面图像输出结构化版面信息。

模型需要输出类似下面这样的严格格式：

```text
<|box_start|>x1 y1 x2 y2<|box_end|><|ref_start|>text<|ref_end|>
```

所以在 MinerU 的 VLM PDF 解析场景里，最怕的不是模型慢，而是模型输出格式乱。

一旦 layout token 输出异常，后面的 PDF 解析逻辑就会出现：

```text
Invalid bbox
Layout output does not match expected format
```

这类 warning。

## 3. vLLM 架构与表现

vLLM 更像一个通用大模型高并发推理服务框架。

在 MinerU + Ascend 910B 场景中，它的链路大概是：

```text
MinerU
  -> vLLM Async Engine
    -> vLLM Ascend / vllm-ascend
      -> torch-npu / CANN
        -> 910B
```

vLLM 的强项包括：

- 高并发推理
- KV cache 管理
- PagedAttention
- OpenAI API 服务化
- 大模型文本生成吞吐
- 多卡 tensor parallel

但是 MinerU 的 PDF 解析不是普通聊天任务，而是要求 VLM 输出极严格的版面结构 token。

普通聊天中，模型偶尔多说几个字问题不大；但 PDF layout 输出中，只要 bbox 多一个 `0`、坐标顺序错、特殊 token 断裂，MinerU 的后处理就可能解析失败。

本次 vLLM 版本中出现过的典型异常包括：

```text
坐标异常：466 906 531 9921
坐标反了：1450 694 423 718
格式乱了：000000000... <fcel> <ecel>
```

因此，本次问题不是 vLLM 完全不能用，而是：

```text
vLLM + Ascend 910B + MinerU VLM layout
```

这个组合在当前版本上不够稳定。

## 4. lmdeploy 架构与表现

lmdeploy 更像是专门为模型部署做的一套推理引擎。MinerU 官方在昇腾 A2 / 910B 上也明确推荐使用 lmdeploy 路线。

在 MinerU + Ascend 910B 场景中，它的链路大概是：

```text
MinerU
  -> LMDeploy VLAsyncEngine
    -> dlinfer / deeplink Ascend
      -> torch-npu / CANN
        -> 910B
```

其中关键组件是：

```text
dlinfer / deeplink Ascend
```

它相当于是 lmdeploy 到昇腾后端之间的适配层。

本次日志中已经确认 MinerU 使用的是 lmdeploy 后端：

```text
Using lmdeploy-engine as the inference engine for VLM.
lmdeploy device is: ascend, lmdeploy backend is: pytorch
```

本次全量测试结果：

```text
63 页
113.64 秒
invalid_bbox_warnings=0
format_warnings=0
```

这说明 lmdeploy 在这台 910B3 上生成 MinerU 所需的 layout token 更稳定。

## 5. PDF 解析场景下的关键区别

| 维度 | vLLM | lmdeploy |
|---|---|---|
| 定位 | 通用高性能 LLM/VLM 推理框架 | 模型部署推理框架，MinerU Ascend 路线更贴合 |
| 910B 适配 | 依赖 vllm-ascend 等适配 | 通过 dlinfer / deeplink Ascend 适配 |
| 普通文本生成 | 很强 | 也强 |
| MinerU layout 输出 | 当前环境不稳定 | 当前环境稳定 |
| 特殊 token 格式 | 出现错乱 | 当前测试未出现错乱 |
| 单卡启动 | 可直接挂 `/dev/davinci4` | 也可单卡，但建议设置 `ASCEND_DEVICE_ID=0` |
| 本次实测速度 | 约 207 秒且有 warning | 113 秒且 0 warning |
| 推荐用途 | 通用 LLM 服务、并发、OpenAI API 兼容 | 当前 MinerU + 910B PDF 解析主路线 |

## 6. 为什么 lmdeploy 在这里更合适

PDF 解析不是普通推理任务，它有三个特殊点。

### 6.1 输出必须是机器可解析格式

MinerU 依赖模型输出的 bbox、ref 标签、box 标签来还原 PDF 页面结构。

这些内容必须符合严格格式：

```text
<|box_start|>x1 y1 x2 y2<|box_end|><|ref_start|>type<|ref_end|>
```

如果坐标异常、标签断裂、token 重复，后处理就无法可靠解析。

### 6.2 页面图像输入较长

PDF 页面会先转成图片，VLM 需要同时处理图像 token 和文本提示词。

对于多页文档，输入和输出都可能比较长，这对推理引擎的上下文处理和生成稳定性要求更高。

### 6.3 后处理强依赖模型输出格式

MinerU 的 `parse_layout_output` 很依赖模型按协议输出。

模型输出如果类似下面这样：

```text
<|box_start|>466 906 531 9921<|box_end|><|ref_start|>page_number<|ref_end|>
```

或者：

```text
000000000000000000000<fcel><ecel>
```

后处理就会认为这是无效 bbox 或不符合预期格式。

因此，这个任务对推理引擎的要求不是单纯“快”，而是：

- 稳定生成特殊 token
- 不重复刷数字
- 不截断关键结构
- 不破坏 bbox 格式
- 不乱处理图文上下文

## 7. 当前实测结果

### 7.1 lmdeploy 小范围测试

测试命令：

```bash
START_PAGE=0 END_PAGE=3 bash ./test.sh "./xxxx（2025年修订版）.pdf"
```

结果：

```text
http_code=200
time_total=16.683893
markdown_lines=68
markdown_chars=904
images=0
json_files=4
invalid_bbox_warnings=0
format_warnings=0
```

### 7.2 lmdeploy 全量测试

测试命令：

```bash
START_PAGE=0 END_PAGE=62 bash ./test.sh "./xxxx（2025年修订版）.pdf"
```

结果：

```text
http_code=200
time_total=113.647944
markdown_lines=891
markdown_chars=30240
images=20
json_files=4
invalid_bbox_warnings=0
format_warnings=0
```

全量 63 页耗时约 113.65 秒，平均约：

```text
1.8 秒 / 页
```

这个速度对于 VLM PDF 解析来说是可以接受的，关键是没有 layout warning。

## 8. 运行建议

当前这台 910B3 环境建议以 lmdeploy 为主。

建议保留两个脚本：

```text
run-lmdeploy.sh    # 当前主用
run-vllm.sh        # 保留用于对比和回退
```

监控重点：

- `invalid_bbox_warnings`
- `format_warnings`
- `truncated`
- HTTP 500
- 单文档耗时
- 输出 markdown 行数和字符数是否异常
- 生成图片数量是否异常

## 9. 最终结论

在当前环境中：

```text
硬件：Ascend 910B3
任务：MinerU VLM PDF 解析
模型后端：VLM engine
```

实测表现为：

```text
vLLM：能跑，但 layout 输出异常。
lmdeploy：能跑，速度更快，格式干净。
```

所以当前建议：

```text
MinerU + Ascend 910B3 + PDF VLM 解析
优先使用 lmdeploy 后端
```

一句话总结：

**vLLM 更像通用高速公路，lmdeploy 在当前 MinerU + 910B 的 PDF 解析场景里更像官方铺好的专用车道。**