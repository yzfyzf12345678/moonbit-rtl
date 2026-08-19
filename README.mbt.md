# moonbit-rtl

moonbit-rtl is a MoonBit Verilog-2001 front end for static RTL analysis.
It is useful for small hardware reviews, teaching tools, editor integrations,
and reproducible CI checks.

## Core capabilities

- source-positioned lexical analysis and practical module parsing;
- ANSI ports, packed widths, parameters, expressions, instances, procedural
  blocks, and common case forms;
- configurable declaration, driver, width, reference, dataflow, contract,
  naming, and clock/reset rules;
- design graph, hierarchy, source mapping, project snapshot, and baseline APIs;
- text, JSON, SARIF, Markdown, GitHub annotation, and summary reports;
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

## Architecture

~~~text
source -> lexer -> AST -> expression enrichment
       -> syntax/semantic/width/dataflow/contract rules
       -> reports and CLI adapters
~~~

The main implementation is organized in lexer.mbt, parser.mbt,
advanced_parser.mbt, model.mbt, checker.mbt, analysis.mbt, design_tools.mbt,
dataflow.mbt, reporting.mbt, pipeline.mbt, and project_io.mbt. Generated
interfaces are refreshed by moon info and are not edited by hand.

## Benchmarks

Run the deterministic local benchmark:

~~~bash
moon run cmd --target native -- --benchmark=1000
~~~

The measured command, fixture sizes, toolchain, and machine context are
recorded in BENCHMARKS.md. Measurements are environment-specific observations.

## Tests and CI

The suite includes lexer boundaries, malformed modules, widths, expressions,
instances, source maps, dataflow, contracts, suppressions, baselines,
project snapshots, reports, and benchmark fixtures.

~~~bash
moon fmt
moon info
moon check --target all --deny-warn
moon test --target all --deny-warn
~~~

GitHub Actions repeats formatting, generated-interface, all-target check/test,
native smoke, and production source inventory checks on Ubuntu, macOS, and
Windows. The non-test MoonBit source inventory is validated above 8,000 lines
without counting generated build or dependency output.

The separate publish workflow validates the package and runs moon publish
--frozen only when manually dispatched or when a version tag is pushed.

## License

Apache-2.0. See LICENSE.
