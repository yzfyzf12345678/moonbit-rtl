# moonbit-rtl

MoonBit 编写的 Verilog-2001 RTL 轻量解析与规则检查器，面向 FPGA 教学、硬件代码审查和 CI。

当前版本支持：

- `module`、`input/output/inout`、`wire`、`reg`、位选、`assign`、基础 `always`；
- 重复声明、未驱动输出、未驱动信号、多重驱动、未引用输入诊断；
- MoonBit API、终端诊断和 JSON 诊断；
- MoonBit 0.10.3 的格式化、检查、测试、构建和接口生成 CI。

```bash
moon check --deny-warn
moon test --deny-warn
moon run cmd --target wasm-gc -- --json
```

详细范围、设计边界、后续路线和黑客松申报内容见 [README.mbt.md](README.mbt.md)、[DESIGN.md](DESIGN.md) 与 [PROPOSAL.md](PROPOSAL.md)。

本项目为原创 MoonBit 实现，采用 Apache-2.0 许可证。
