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
| small | 3 | 31 | 655 | 250 | 4 | 336 ms | 74 |
| medium | 9 | 119 | 2606 | 973 | 10 | 1403 ms | 69 |
| large | 25 | 343 | 7634 | 2821 | 27 | 4196 ms | 67 |

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

The same native coverage run executed 42 tests successfully and reported
1,963 covered lines out of 3,779 instrumented lines (52.00%). Coverage is an
engineering signal; the boundary-test count and deterministic fixture counts
remain the primary regression checks.
