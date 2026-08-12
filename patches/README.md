# cryptographyport patches

Patches applied to [cryptography](https://github.com/pypa/cryptography) main
(51.0.0-dev1) for cross-compilation to `s390x-ibm-zos`.

## Files

| File | Purpose |
|------|---------|
| `cryptography/0001-zos-cargo-patches.patch` | Adds `[patch.crates-io]` to `Cargo.toml` for pyo3 (z/OS fork), libc (z/OS fork), and target-lexicon (git main for z/OS triple) |
| `cryptography/0002-zos-cargo-config.patch` | Creates `.cargo/config.toml` at workspace root with z/OS linker, rustc-wrapper, and link-arg settings |
| `cryptography/0003-zos-strerror-stub.patch` | Adds `zos_strerror_stub.c` — pure-C implementation of `__strerror_r_ascii` needed by OpenSSL 4.0.0 |
| `cryptography/rustc-wrapper-crypt.sh` | rustc wrapper script that injects `--extern` flags for proc-macro crates during s390x target compilation |

## Applying the patches

```bash
cd /path/to/cryptography
git apply patches/cryptography/0001-zos-cargo-patches.patch
# Apply 0002 manually: copy .cargo/config.toml
# Apply 0003 manually: copy zos_strerror_stub.c and build libzos_strerror.a on z/OS
# Copy rustc-wrapper-crypt.sh to your toolchain directory and make it executable
```

See the main [README.md](../README.md) for the complete build procedure.

## Why these patches are needed

### `[patch.crates-io]` (patch 1)

- **pyo3**: The upstream pyo3 doesn't support `s390x-ibm-zos`; the IBM fork at
  `github.ibm.com/itodorov/pyo3` (branch `itodorov/zos-support`) adds the z/OS
  target triple, EBCDIC-to-ASCII conversion for Python strings, and z/OS-specific
  build configuration.
- **libc**: The upstream libc crate lacks z/OS definitions; the IBM fork at
  `github.ibm.com/compiler/rust-libc` (branch `zOS.0.2.169`) adds z/OS types,
  constants, and syscall wrappers.
- **target-lexicon**: Pinned to git main for z/OS triple recognition
  (`s390x-ibm-zos`).

### `.cargo/config.toml` (patch 2)

The workspace-root config sets up the cross-compile environment:
- `rustc-wrapper`: points to `rustc-wrapper-crypt.sh` which dynamically injects
  `--extern` flags for proc-macro crates when compiling for the z/OS target
- `linker = "s390x-ibm-zos-cc"`: the LoP→z/OS remote compile wrapper
- `link-arg=/usr/lpp/IBM/cyp/v3r12/pyz/lib/libpython3.12.x`: z/OS side-deck for
  libpython (required by PyO3)
- `link-arg=-lzos_strerror`: links the `__strerror_r_ascii` stub
- `-C target-feature=-vector`: disables LLVM auto-vectorisation (z/OS GOFF
  cross-compilation doesn't support inline vector asm)

### `__strerror_r_ascii` stub (patch 3)

OpenSSL 4.0.0 as built by zopencommunity calls `__strerror_r_ascii()` — a
z/OS ASCII-mode error string function. This symbol is defined in `libzoslib.a`
(a C++ library), but:

1. `libzoslib.a` members import `libzoslib.so` at runtime (z/OS DLL mechanism)
2. Linking against `libzoslib.a` causes the z/OS binder to add a DLL dependency
   on `libzoslib.so`
3. More critically: libzoslib references C++ runtime symbols (`_ZSt9terminatev`,
   `__cxa_guard_release`) that ibm-clang only provides when linking as C++

The stub implements `__strerror_r_ascii` using `strerror()` (EBCDIC output) and
`__e2a_l()` (IBM built-in EBCDIC→ASCII converter), avoiding the C++ dependency.

### `rustc-wrapper-crypt.sh`

The `asn1` crate does:
```rust
pub use asn1_derive::{oid, Asn1DefinedByRead, Asn1DefinedByWrite, Asn1Read, Asn1Write};
```

When Cargo 1.86 cross-compiles `asn1` for `s390x-ibm-zos`, it compiles
`asn1_derive` (a proc-macro) for the host but does **not** pass
`--extern asn1_derive=<host.so>` to the `asn1` target compilation, even though
`pub use` requires the crate to be resolvable. Same applies to `openssl_macros`
and `pyo3_macros`.

The wrapper intercepts rustc invocations for the z/OS target, finds the
proc-macro `.so` files that Cargo already built in `target/release/deps/`, and
injects them as `--extern` flags. It uses the `--out-dir` argument to locate
the correct `target/release/deps/` directory regardless of workspace layout.
