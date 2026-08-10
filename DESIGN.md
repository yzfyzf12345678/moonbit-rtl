# Design notes

## Boundary

The first release is an RTL front end for small Verilog-2001 designs. It is not a synthesizer, simulator, or complete IEEE grammar implementation. Keeping this boundary explicit makes diagnostics predictable and leaves room for a compatible SystemVerilog layer.

## Pipeline

```text
source -> lexer -> lightweight AST -> rule engine -> terminal/JSON
```

The AST owns source spans so future rules can report precise locations without coupling the rule engine to token details. Output formatting is kept separate from analysis so a SARIF adapter can be added without changing checks.

## Rule identifiers

`RTL001` is reserved for width mismatch, `RTL002` duplicate declaration, `RTL003` undriven output, `RTL004` undriven internal signal, `RTL005` multiple drivers, and `RTL006` unused input. The identifiers are stable integration points for editor and CI clients.

## Planned extensions

The next increments are file input and exit-status handling in the CLI, richer expression widths, `case` and instance AST nodes, configurable severity, SARIF output, and a language-server adapter. None of these are claimed as complete in version 0.1.0.
