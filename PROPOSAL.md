# MoonBit RTL 设计规则检查器

项目名称：MoonBit RTL 设计规则检查器

项目标识：`moonbit-rtl`

GitHub：https://github.com/yzfyzf12345678/moonbit-rtl

Gitlink：https://gitlink.org.cn/yzfyzf/moonbit-rtl

## 项目简介

本项目是面向 Verilog-2001 常用语法的 MoonBit RTL 解析与静态检查工具，服务于 FPGA 教学、硬件课程作业、开源 RTL 审查和持续集成。项目使用 MoonBit 实现词法分析、轻量 AST、规则引擎及诊断输出，避免依赖完整综合器即可快速发现常见结构性错误。

## 现有基础

当前已支持 `module`、`input/output/inout`、`wire`、`reg`、位选声明、`assign` 和基础 `always` 块；已实现重复声明、未驱动输出、未驱动信号、多重驱动和未引用输入检查，并提供终端与 JSON 诊断格式。仓库包含可运行示例、自动化测试、Apache-2.0 许可证和跨平台 MoonBit CI。

## 本次开发计划

1. 完善表达式与位宽传播，补充 `case`、条件语句、模块实例化和端口连接 AST。
2. 增加 Verilog 文件输入 CLI、稳定退出码、SARIF 输出和规则级配置。
3. 扩充真实 RTL fixtures、错误恢复测试、性能基准及可复现文档。
4. 在兼容现有 API 的基础上，逐步加入 SystemVerilog 常用子集、LSP 适配和自动修复建议。

## 技术路线与交付物

采用 lexer、AST、parser、rule engine、reporter 分层结构；通过源代码位置保留和稳定规则编号支持 CI 与编辑器集成。最终交付 MoonBit 可复用库、命令行工具、JSON/终端诊断、示例工程、测试集、CI、设计文档和版本变更记录。

## 原创与开源说明

本项目为原创 MoonBit 开发工具，不是其他项目的直接移植，不包含第三方源代码、闭源代码、商业代码或来源不明的生成内容。项目采用 OSI 认可的 Apache-2.0 许可证，第三方依赖和测试素材将继续保持来源、版权与许可证记录。
