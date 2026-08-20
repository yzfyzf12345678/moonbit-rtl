# moonbit-rtl

moonbit-rtl is a MoonBit Verilog-2001 front end for practical RTL analysis.
It turns HDL text into a source-spanned model and produces diagnostics,
simulation traces, timing/coverage evidence, and machine-readable reports for
hardware review, editor tooling, and reproducible CI.

## Project positioning

The package is a deterministic analysis and verification toolkit. It is not a
synthesizer and does not claim to replace a complete IEEE Verilog
implementation. The supported subset is intentionally explicit and designed
for reusable tooling and small-to-medium RTL review workflows.

## Core capabilities

- source-positioned lexical analysis and practical module parsing;
- ANSI ports, packed widths, parameters, expressions, instances, procedural
  blocks, and common case forms;
- configurable declaration, driver, width, reference, dataflow, contract,
  naming, clock/reset, and advanced rule-pack checks;
- preprocessor, four-state bit vectors, fixed-point simulation, hierarchy,
  timing, coverage, intermediate IR, LSP, query, and netlist APIs;
- verification vectors, trace capture/replay, release evidence, and
  text, JSON, SARIF, Markdown, GitHub annotation, and summary reports;
- native CLI with file input, token output, rule controls, and benchmarks.

## Quick start

~~~bash
moon update
moon check --deny-warn
moon test --deny-warn
moon run cmd --target native -- --summary
~~~

Check a source file with the CLI:

~~~bash
moon run cmd --target native -- --file examples/basic.v --json
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=large
~~~

Library usage:

~~~mbt nocheck
let result = @yzfyzf12345678/moonbit-rtl/src.run_default_pipeline(source)
println(result.status_line())
~~~

## CLI

~~~text
--file PATH          read a Verilog source file
--json               emit JSON diagnostics
--sarif              emit SARIF 2.1.0
--markdown           emit a Markdown diagnostic table
--summary            print counts and rule IDs
--tokens             print tokens with source positions
--disable=RTLxxx     disable one rule
--max-diagnostics N  cap emitted findings
--benchmark[=N]      run the deterministic benchmark
~~~

## Architecture

~~~text
source -> preprocessor -> lexer/parser -> enriched AST
       -> checker/width/dataflow/hierarchy/timing/coverage
       -> simulation/IR/query/netlist/verification
       -> reports, CLI, editor, CI, and release evidence
~~~

The implementation is organized into cohesive MoonBit modules. Generated
interfaces are refreshed by `moon info` and are not edited by hand.

## Benchmarks

Run the deterministic local benchmark:

~~~bash
moon run cmd --target native -- --benchmark=1000
~~~

The measured command, fixture sizes, toolchain, and machine context are
recorded in BENCHMARKS.md. The current run observed 74, 72, and 70 tokens/ms
for the small, medium, and large fixtures respectively. Measurements are
environment-specific observations.

The current local inventory contains 20,040 non-test production MoonBit lines
across 38 files. The recorded native run uses 100 rounds per fixture; small,
medium, and large fixtures report 46, 75, and 73 tokens/ms respectively on
the documented machine.

## Tests and CI

The suite contains 61 passing tests covering lexer and parser boundaries,
preprocessing, four-state vectors, simulation, advanced rules, queries,
netlists, verification vectors, trace replay, source maps, dataflow,
contracts, reports, snapshots, and benchmark fixtures.

~~~bash
moon fmt
moon info
moon check --target all --deny-warn
moon test --target all --deny-warn
~~~

GitHub Actions repeats formatting, generated-interface, all-target check/test,
native smoke, and production source inventory checks on Ubuntu, macOS, and
Windows. The non-test MoonBit source inventory is validated at or above
20,000 lines without counting generated build, dependency, or test output.

The separate publish workflow validates the package and runs `moon publish`
when manually dispatched or when a version tag is pushed. It reads the
repository's Mooncakes credentials secret only during that step and removes
the temporary credentials afterwards.

## License

Apache-2.0. See LICENSE.
