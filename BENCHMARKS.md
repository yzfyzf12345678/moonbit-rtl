# Benchmarks

This document records an observed native CLI run of the deterministic fixtures.
It is a reproducibility record, not a performance guarantee.

## Environment

- Date: 2026-08-19
- OS: Windows
- CPU: AMD Ryzen 7 5800H, 8 cores / 16 logical processors
- MoonBit: moon 0.1.20260807, moonc v0.10.7+bc794d341
- Run mode: native target, warm local build, 100 rounds per fixture

## Measured run

Command:

~~~text
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=small
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=medium
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=large
~~~

Observed output:

| Fixture | Modules | Source lines | Bytes | Tokens / round | Diagnostics / round | Total elapsed | Tokens / ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small | 3 | 31 | 655 | 250 | 4 | 542 ms | 46 |
| medium | 9 | 119 | 2606 | 973 | 10 | 1286 ms | 75 |
| large | 25 | 343 | 7634 | 2821 | 27 | 3845 ms | 73 |

The CLI reports aggregate token and diagnostic counts over all rounds. The
fixture diagnostics are expected findings from the current rule policy; the
benchmark measures parser and checker work rather than claiming that each
fixture is warning-free.

## Reproduce

~~~bash
moon fmt
moon info
moon check --target native --deny-warn
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=small
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=medium
moon run cmd --target native -- --benchmark=100 --benchmark-fixture=large
~~~

Wall-clock values depend on CPU, operating-system scheduling, toolchain, and
build state. Compare source size, token counts, and diagnostic counts before
comparing elapsed time.

The same native coverage run executed 61 tests successfully and reported
3,612 covered lines out of 8,674 instrumented lines (41.64%). Coverage is an
engineering signal; the boundary-test count and deterministic fixture counts
remain the primary regression checks.
