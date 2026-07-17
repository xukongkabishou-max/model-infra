# DeepSeek-V4 日志输出信息说明

## 1. 原始日志

```text
SpecDecoding metrics: Mean acceptance length: 1.47, Accepted throughput: 3.10 tokens/s, Drafted throughput: 6.60 tokens/s, Accepted: 31 tokens, Drafted: 66 tokens, Per-position acceptance rate: 0.470, Avg Draft acceptance rate: 47.0%
```

这条日志来自 vLLM 的 Speculative Decoding（推测解码）统计模块，用于描述 MTP 草稿 Token 的产生、验证和接受情况。

MTP 是 Multi-Token Prediction（多 Token 预测）。

当前服务使用的推测解码配置为：

```json
{
  "num_speculative_tokens": 1,
  "method": "mtp"
}
```

含义是：主模型每轮正常解码时，MTP 模块额外提出 1 个候选 Token，再由主模型验证该候选是否正确。

## 2. 指标总览

| 指标 | 当前值 | 中文说明 |
| --- | ---: | --- |
| `Mean acceptance length` | `1.47` | 每轮验证完成后，解码过程平均可以向前推进 1.47 个 Token |
| `Accepted throughput` | `3.10 tokens/s` | 每秒被主模型验证并接受的 MTP 推测 Token 数量 |
| `Drafted throughput` | `6.60 tokens/s` | MTP 模块每秒提出的候选 Token 数量 |
| `Accepted` | `31 tokens` | 当前统计周期内，被验证通过的推测 Token 总数 |
| `Drafted` | `66 tokens` | 当前统计周期内，MTP 一共提出的候选 Token 总数 |
| `Per-position acceptance rate` | `0.470` | 第 1 个推测位置的接受率为 47% |
| `Avg Draft acceptance rate` | `47.0%` | 所有推测 Token 的平均接受率为 47% |

## 3. Mean acceptance length

`Mean acceptance length` 表示每执行一次主模型验证，解码过程平均能够推进多少个 Token。

当前配置每轮只推测 1 个 Token：

- 如果推测错误，本轮仍然能够得到主模型计算出的 1 个有效 Token。
- 如果推测正确，本轮能够得到 1 个主模型 Token和 1 个被接受的推测 Token，共推进 2 个 Token。

因此平均推进长度近似为：

```text
平均推进长度
= 1 个主模型保证产生的 Token + 推测 Token 接受率
= 1 + 0.47
= 1.47
```

日志中的 `Mean acceptance length: 1.47` 与 47% 的接受率完全对应。

这表示普通解码每轮通常推进 1 个 Token，而当前 MTP 配置平均每轮推进 1.47 个 Token。

## 4. Accepted 与 Drafted

### Drafted

```text
Drafted: 66 tokens
```

表示在当前统计周期内，MTP 模块总共提出了 66 个候选 Token。

这些 Token 只是候选结果，不能直接返回给用户，必须经过主模型验证。

### Accepted

```text
Accepted: 31 tokens
```

表示 66 个候选 Token 中有 31 个与主模型验证结果一致，因此可以直接接受并加入最终输出。

未被接受的数量为：

```text
拒绝数量
= Drafted - Accepted
= 66 - 31
= 35 tokens
```

因此，这个统计周期中共有 31 个推测 Token 被接受，35 个推测 Token 被拒绝。

## 5. 接受率计算

平均接受率的计算方式为：

```text
接受率
= Accepted / Drafted
= 31 / 66
≈ 0.4697
≈ 47.0%
```

这与日志中的两项数据一致：

```text
Per-position acceptance rate: 0.470
Avg Draft acceptance rate: 47.0%
```

当前只配置了 1 个推测 Token，所以只有第 1 个推测位置；因此 `Per-position acceptance rate` 与整体平均接受率相同。

如果以后把 `num_speculative_tokens` 调整为 2 或 3，日志可能会显示多个位置的接受率。通常越靠后的推测位置越难预测准确，接受率也可能逐级下降。

## 6. Accepted throughput 与 Drafted throughput

### Drafted throughput

```text
Drafted throughput: 6.60 tokens/s
```

表示 MTP 模块平均每秒产生 6.60 个候选 Token。

### Accepted throughput

```text
Accepted throughput: 3.10 tokens/s
```

表示每秒大约有 3.10 个候选 Token 被主模型验证并接受。

两者的比例为：

```text
Accepted throughput / Drafted throughput
= 3.10 / 6.60
≈ 0.4697
≈ 47.0%
```

该结果同样与接受率一致。

需要注意，`Accepted throughput` 不是服务完整的生成速度。它只统计被接受的推测 Token，不包含主模型正常生成的 Token。

整体生成速度应查看以下指标之一：

- vLLM 日志中的 `Avg generation throughput`
- 连续调用测试中的 `decode`
- 并发压测中的 `output_throughput`

## 7. 当前结果评价

47% 的接受率说明 MTP 推测解码功能正在正常运行，但接受效果属于中等水平。

它意味着：

- MTP 提出的候选 Token 中，约每两个有一个能够被接受。
- 每轮验证平均从普通解码的 1 个 Token 提升到 1.47 个 Token。
- 一部分主模型逐 Token 解码轮次被节省。
- 仍有 53% 的候选 Token 验证失败，其推测和验证开销不能完全转化为有效输出。

47% 并不是错误，也不表示服务异常。接受率会受到以下因素影响：

- 提示词内容和任务类型
- 输出内容的可预测程度
- `temperature`、`top_p` 等采样参数
- 当前生成处于推理阶段还是最终回答阶段
- 并发负载与批处理状态
- MTP 权重本身的预测能力
- 统计窗口大小

单个统计窗口的数据不能代表服务长期平均水平，应在完整压测周期内观察多条日志。

## 8. 与 90% 接受率日志的对比

服务此前还出现过以下统计：

```text
Mean acceptance length: 1.90
Avg Draft acceptance rate: 90.0%
```

两组结果的关系如下：

| 接受率 | 平均推进长度 | 说明 |
| ---: | ---: | --- |
| 47% | 1.47 Token/轮 | 当前统计窗口中约一半推测成功 |
| 90% | 1.90 Token/轮 | 当前统计窗口中绝大多数推测成功 |

这说明 MTP 接受率会随实际请求动态变化，并不是固定值。

## 9. 是否获得实际加速

不能只根据 `Mean acceptance length: 1.47` 判断服务获得了 1.47 倍加速。

推测解码还会产生以下额外开销：

- MTP 候选 Token 计算
- 主模型批量验证
- 接受或拒绝判断
- NPU 算子调度
- 多卡通信与同步

因此，真实净收益必须通过相同请求集进行 A/B 对比。

### 开启 MTP

```bash
--speculative-config '{"num_speculative_tokens":1,"method":"mtp"}'
```

### 关闭 MTP

启动参数中移除 `--speculative-config`。

两组测试应保持以下条件一致：

- 模型权重一致
- 输入请求集一致
- 并发度一致
- 最大输出 Token 数一致
- 采样参数一致
- 服务预热状态一致
- Prefix Cache 状态一致

重点对比：

| 指标 | 关注方向 |
| --- | --- |
| TTFT | 越低越好 |
| 平均端到端延迟 | 越低越好 |
| P95/P99 延迟 | 越低且越稳定越好 |
| 单请求 Decode 速度 | 越高越好 |
| `output_throughput` | 越高越好 |
| 并发请求总吞吐 | 越高越好 |

如果开启 MTP 后输出吞吐提高或延迟降低，说明 MTP 带来了净收益。

如果接受率长期偏低，并且整体吞吐没有提升，说明推测与验证开销可能抵消了收益，此时可以考虑关闭 MTP 后重新测试。

## 10. 最终结论

> 当前 MTP 推测解码运行正常。在本次统计周期内，MTP 共提出 66 个候选 Token，其中 31 个通过主模型验证，平均接受率为 47%。在每轮只推测 1 个 Token 的配置下，解码过程平均每轮推进 1.47 个 Token。该结果表明 MTP 产生了有效的加速机会，但是否带来最终净性能提升，仍需要与关闭 MTP 时的相同负载测试结果进行对比。

