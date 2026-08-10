# moonbit-rtl

`moonbit-rtl` 是一个用 MoonBit 编写的 Verilog-2001 RTL 语法与规则检查器，面向 FPGA 教学、课程作业和硬件代码审查。它把 HDL 文本解析为轻量 AST，再输出稳定的终端诊断或 JSON 诊断，方便接入 CI。

## 当前范围

- 支持 `module`、端口方向、`wire`、`reg`、位选声明、`assign` 和基础 `always` 块。
- 规则覆盖重复声明、未驱动输出、未驱动内部信号、多重驱动和未引用输入。
- 诊断包含规则编号、严重级别、行列位置和信号名。
- 解析器和检查器均提供 MoonBit API，后续可扩展 SystemVerilog 子集、LSP 和自动修复。

## 运行

需要 MoonBit 0.10.3 或更高版本。

```bash
moon run cmd --target native
moon run cmd --target native -- --json
moon check --deny-warn
moon test --deny-warn
```

当前命令行演示使用内置样例；库 API 可直接检查任意字符串：

```mbt nocheck
let diagnostics = @studentyang/moonbit-rtl/src.check_source(verilog_source)
println(@studentyang/moonbit-rtl/src.diagnostics_text(diagnostics))
```

## 设计说明

项目刻意把词法、AST、解析和规则分开。语法树只保留规则检查需要的结构，不尝试替代完整的综合器或仿真器。这样可以在不改变核心 API 的前提下，逐步加入实例化、参数、`case`、SystemVerilog 语法、SARIF/JSON Schema 输出以及 LSP 适配。

## 来源与许可证

这是原创 MoonBit 实现，不包含第三方源代码、闭源代码或生成代码。测试样例由项目维护者编写。项目采用 Apache-2.0 许可证，见 [LICENSE](LICENSE)。

## 参赛申报范围

本项目参加 2026 MoonBit 国产基础软件生态开源大赛 8 月黑客松，当前阶段聚焦可复用的 Verilog RTL 前端与静态规则框架。后续开发记录、测试记录和 CI 结果均保留在仓库中。
