# Step 1 — Unpack the toolkit and port `dsdgen` to macOS/arm64

## Goal

Build `dsdgen` so that `dsdgen -SCALE 1` runs.

## Starting point

```
dw/
└── 3A8E7D3F-9839-49E1-B7E7-4DA904F08EDB-TPC-DS-Tool.zip   7.5 MB
```

Unpacked to `DSGen-software-code-4.0.0/` (the `__MACOSX/` resource-fork
directory the zip carried was removed).

## The problem

The toolkit ships one makefile (`tools/Makefile.suite`, copied verbatim to
`tools/makefile`) with a single `OS` switch:

```make
# OS Values: AIX, LINUX, SOLARIS, NCR, HPUX
OS = LINUX
```

There is no Darwin or macOS target, and `OS=LINUX` does not work here:

1. `config.h` defines `USE_VALUES_H` for LINUX, so `porting.h` includes
   `<values.h>` — a glibc header that does not exist on macOS. `MAXINT` comes
   from that header.
2. Thirteen source files include `<malloc.h>`, which macOS does not have
   (`malloc` is declared in `<stdlib.h>`).
3. The code is K&R-era C. Clang 15+ makes implicit function declarations,
   int↔pointer conversions and incompatible pointer assignments hard errors
   rather than warnings.

## What was changed

Rather than bending the LINUX target, a first-class `MACOS` target was added,
so the LINUX build stays intact. Originals are preserved as `*.orig`.

### `tools/makefile` and `tools/Makefile.suite`

`MACOS_*` entries added alongside the existing per-OS blocks, and the target
switched:

```make
# OS Values: AIX, LINUX, MACOS, SOLARIS, NCR, HPUX
OS = MACOS

MACOS_CC     = cc
MACOS_CFLAGS = -g -Wall -Wno-format -Wno-implicit-int \
               -Wno-deprecated-non-prototype \
               -Wno-error=implicit-function-declaration \
               -Wno-error=int-conversion \
               -Wno-error=incompatible-pointer-types
MACOS_EXE    =
MACOS_LEX    = flex
MACOS_LIBS   = -lm
MACOS_YACC   = bison -y
MACOS_YFLAGS = -d -v
```

The `-Wno-error=` flags demote clang's new hard errors back to warnings. They
do not silence anything: the build still prints the warnings.

### `tools/config.h`

New block mirroring LINUX, but drawing `MAXINT` from `<limits.h>`:

```c
#ifdef MACOS
#define SUPPORT_64BITS
#define HUGE_TYPE	int64_t
#define HUGE_FORMAT	"%lld"
#define HUGE_COUNT	1
#define USE_STRING_H
#define USE_LIMITS_H      /* LINUX uses USE_VALUES_H; macOS has no <values.h> */
#define USE_STDLIB_H
#define FLEX
#endif /* MACOS */
```

### `tools/porting.h`

```c
#ifdef MACOS
#include <limits.h>
#define MAXINT INT_MAX
#endif /* MACOS */
```

**This one matters for correctness, not just compilation.** `genrand.c`
implements the Lehmer minimal-standard RNG with multiplier 16807, quotient
127773 and remainder 2836 — constants that are only valid for the modulus
2147483647. That modulus is `MAXINT`. On Linux `<values.h>` defines
`MAXINT` as `INT_MAX`, so taking it from `<limits.h>` reproduces the value
exactly and the generated data is bit-identical to a Linux build. Defining
`MAXINT` as anything else would silently produce a different data set.

### Thirteen source files

`w_call_center.c`, `date.c`, `permute.c`, `dist.c`, `dcgram.c`, `dcomp.c`,
`w_household_demographics.c`, `misc.c`, `query_handler.c`, `decimal.c`,
`StringBuffer.c`, `tokenizer.l`, `tokenizer.c` — each had:

```c
#include <malloc.h>
```

replaced by:

```c
#ifdef MACOS
#include <stdlib.h>
#else
#include <malloc.h>
#endif
```

## Result

```
$ make
...
$ ls -la dsdgen dsqgen distcomp mkheader checksum tpcds.idx
-rwxr-xr-x  checksum     34,216
-rwxr-xr-x  distcomp     76,472
-rwxr-xr-x  dsdgen      322,856
-rwxr-xr-x  dsqgen      226,584
-rwxr-xr-x  mkheader     34,248
-rw-r--r--  tpcds.idx   640,585
```

All five executables build, plus `tpcds.idx` (the compiled distribution file
that `distcomp` produces from the `.dst` sources; both `dsdgen` and `dsqgen`
require it at runtime). No errors — warnings only.

`bison 2.3` and `flex 2.6.4` were already present at `/usr/bin`, so the
grammar and tokenizer regenerate without extra tooling.

## Reverting

```sh
cd DSGen-software-code-4.0.0/tools
for f in config.h porting.h makefile Makefile.suite; do cp "$f.orig" "$f"; done
```
