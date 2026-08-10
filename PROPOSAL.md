# MoonBit RTL 设计规则检查器

- 项目方向：原创 MoonBit 开发工具
- 项目简介：面向 Verilog-2001 常用语法，提供轻量 AST、规则检查、终端与 JSON 诊断，服务 FPGA 教学、硬件代码审查和 CI。
- 现有基础：已实现 module/port/wire/reg/assign/always 子集的词法分析、解析和规则检查 API，并提供可运行示例与测试。
- 本次计划：完善端口与位宽语义、扩展 `case`/实例化、增加 SARIF 输出和文件输入 CLI，补充更多真实 RTL fixtures 与性能基准。
- 技术路线：MoonBit 分层实现 lexer、AST、parser、rule engine；用稳定的诊断模型隔离规则与输出格式；通过 GitHub Actions 执行格式化、构建、测试和 `moon info` 检查。
- 预期交付：可复用 MoonBit 库、原生 CLI、JSON/终端诊断、测试集、CI、README 与后续 SystemVerilog/LSP 扩展路线。
- 来源说明：原创实现，无移植代码；许可证为 Apache-2.0。
