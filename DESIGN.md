# Design notes

## Boundary

The first release is an RTL front end for small Verilog-2001 designs. It is not a synthesizer, simulator, or complete IEEE grammar implementation. Keeping this boundary explicit makes diagnostics predictable and leaves room for a compatible SystemVerilog layer.

## Pipeline

```text
source -> normalization -> lexer/spans -> lightweight AST
       -> expression and instance enrichment
       -> syntax/semantic/width/dataflow/contract rules
       -> terminal/JSON/SARIF/Markdown/CI adapters
```

The AST owns source spans so future rules can report precise locations without coupling the rule engine to token details. Output formatting is kept separate from analysis so a SARIF adapter can be added without changing checks.

## Rule identifiers

`RTL001` is reserved for width mismatch, `RTL002` duplicate declaration,
`RTL003` undriven output, `RTL004` undriven internal signal, `RTL005` multiple
drivers, and `RTL006` unused input. Extended rules use the RTL008-RTL051 range.
The identifiers are stable integration points for editor and CI clients.

## Extension points

The current API leaves room for a fuller SystemVerilog grammar, language-server
transport, richer constant propagation, and synthesis-aware policies. These
can be added behind the existing source-span, rule-configuration, and report
interfaces without changing the basic CLI contract.
