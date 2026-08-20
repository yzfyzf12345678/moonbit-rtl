# moonbit-rtl

moonbit-rtl is a MoonBit Verilog-2001 front end for small RTL reviews,
teaching tools, and reproducible CI checks. It turns HDL text into a
source-spanned lightweight design model, then applies syntax, width,
connectivity, dataflow, and interface rules.

## Project positioning

The project is a static analysis and reporting library, not a synthesizer,
simulator, or replacement for a complete IEEE Verilog implementation. Its
small, deterministic core is intended for editor tooling, courseware,
pre-commit checks, and hardware code-review services.

## Core capabilities

- source-positioned lexer with comments, strings, directives, escaped names,
  literals, and multi-character operators;
- practical parser for modules, ANSI ports, packed widths, parameters,
  declarations, assignments, procedural blocks, expressions, instances, and
  common case forms;
- configurable diagnostics for declarations, drivers, references, widths,
  procedural hazards, instances, naming, clock/reset conventions, dataflow,
  and interface contracts;
- reusable design graph, symbol index, hierarchy, width, dataflow, and source
  mapping APIs;
- text, JSON, JSON Lines, SARIF, Markdown, GitHub annotation, and summary
  reports;
- native CLI with file input, token inspection, rule suppression, diagnostic
  limits, and deterministic benchmark mode.

## Quick start

Install the current stable MoonBit toolchain, then run:

~~~bash
moon update
moon check --deny-warn
moon test --deny-warn
moon run cmd --target native
~~~

The command checks the built-in example. Check a file or select an output:

~~~bash
moon run cmd --target native -- --file examples/basic.v --summary
moon run cmd --target native -- --file examples/basic.v --json
moon run cmd --target native -- --file examples/basic.v --sarif
~~~

## CLI

~~~text
--file PATH          read a Verilog source file
--json               emit JSON diagnostics
--sarif              emit SARIF 2.1.0
--markdown           emit a Markdown table
--summary            print counts and rule IDs
--tokens             print tokens with line and column
--no-info            suppress informational findings
--disable=RTLxxx     disable one rule
--max-diagnostics N  cap emitted findings
--benchmark[=N]      run the deterministic parser/checker benchmark
--benchmark-fixture  select small, medium, or large benchmark source
~~~

The library API is available from yzfyzf12345678/moonbit-rtl/src:

~~~mbt nocheck
let result = @yzfyzf12345678/moonbit-rtl/src.run_default_pipeline(source)
println(result.status_line())
println(result.render(@yzfyzf12345678/moonbit-rtl/src.JsonReport))
~~~

## Architecture

~~~text
source
  -> lexer and source spans
  -> legacy-compatible AST
  -> expression/instance/procedural enrichment
  -> syntax, semantic, width, dataflow, and contract rules
  -> reports, CLI, editor and CI adapters
~~~

The implementation is split into cohesive modules: lexer/parser and source
mapping; model, checker, extra rules, dataflow, width, contract, and pipeline
analysis; preprocessing, four-state bit vectors, simulation, elaboration,
timing, coverage, intermediate IR, advanced rules, project configuration,
LSP, query, netlist, verification, release reporting, and trace replay.
Generated interfaces are refreshed by moon info; they are never hand-edited.

## Benchmarks

BENCHMARKS.md records reproducible local measurements for the checked-in
small, medium, and large fixtures, including command lines, toolchain version,
hardware context, source sizes, and observed throughput. The measurements are
observations for one environment, not performance guarantees.

~~~bash
moon run cmd --target native -- --benchmark=1000
~~~

## Tests

The test suite contains 61 passing tests and covers empty input, comments and
strings, source coordinates, operators, ANSI widths, parameters, expressions,
instances, malformed modules, preprocessor directives, four-state vectors,
simulation, rule profiles, netlist boundaries, query cones, verification
vectors, trace replay, report formats, source maps, dataflow, contracts,
suppressions, baselines, edits, project snapshots, and benchmark fixtures.

~~~bash
moon fmt
git diff --exit-code
moon info
git diff --exit-code
moon check --target all --deny-warn
moon test --target all --deny-warn
~~~

The local production inventory contains 20,040 non-test MoonBit source lines
across 38 source files, excluding generated build, dependency, and test output.
CI recomputes this inventory instead of relying on a claimed number. The
native coverage run observed 3,612 covered out of 8,674 instrumented lines
(41.64%); coverage is reported as an engineering signal rather than a claim
that every production branch is exercised.

## CI

GitHub Actions runs the current stable MoonBit installer on Ubuntu, macOS, and
Windows. It verifies formatting, generated interfaces, all-target checks,
all-target tests, native build/test smoke coverage, and the production source
inventory. A separate manual/tag workflow validates and publishes the package
with `moon publish` using the repository's Mooncakes credentials secret. The
workflow writes the credentials only for the publish step and removes them
afterwards. See `.github/workflows/moon.yml` and
`.github/workflows/publish.yml`.

## License

Apache-2.0. See LICENSE.
