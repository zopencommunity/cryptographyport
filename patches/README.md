# cryptography z/OS Cross-Compilation Patches

Cross-compile [cryptography](https://github.com/pypa/cryptography) for
`s390x-ibm-zos` from a Linux-on-Power host using the Flask HTTP cross-compile
server infrastructure in this repo.

## Tested version

`50.0.0` (official release tag), built with OpenSSL 4.0.0 static linkage.

## Dependencies on z/OS

- Python 3.12 — `/usr/lpp/IBM/cyp/v3r12/pyz/bin/python3`
- cffi — already available via IBM Open Enterprise Python 3.12
- **OpenSSL 4.0.0** — from zopencommunity (`~/zopen/usr/local/lib/{libssl,libcrypto}.a`)
- **libzoslib** — from zopencommunity (`~/zopen/usr/local/lib/libzoslib.so`)
  - Required at runtime via `LIBPATH=/home/itodoro/zopen/usr/local/lib:$LIBPATH`

## Build setup

### 1. Copy z/OS sysroot to LoP

```bash
# OpenSSL headers and static libs
mkdir -p /tmp/zos-sysroot/openssl/{include/openssl,lib}
scp itodoro@zoscan2b:/home/itodoro/zopen/usr/local/lib/libssl.a /tmp/zos-sysroot/openssl/lib/
scp itodoro@zoscan2b:/home/itodoro/zopen/usr/local/lib/libcrypto.a /tmp/zos-sysroot/openssl/lib/
# Copy headers via Python (avoids EBCDIC encoding issues)
# Run gen_openssl_headers.sh or copy from /home/itodoro/zopen/usr/local/include/openssl/

# Python 3.12 headers (copy with _BPXK_AUTOCVT=ON from z/OS)
# See cross/patches/pyo3-zos/README.md for the Python headers tarball method

# Build and copy the strerror stub
scp zos_strerror_stub.c itodoro@zoscan2b:/tmp/
ssh itodoro@zoscan2b '
  chtag -tc ISO8859-1 /tmp/zos_strerror_stub.c
  BIN=/c390/archive/wozdrivers/continuous/openxlC/zOS/v220z/176/bin
  $BIN/ibm-clang -target s390x-ibm-zos --config=$BIN/le31.cfg \
    -fzos-le-char-mode=ascii -c /tmp/zos_strerror_stub.c -o /tmp/zos_strerror_stub.o
  /bin/ar -r /home/itodoro/zopen/usr/local/lib/libzos_strerror.a /tmp/zos_strerror_stub.o
'
```

### 2. Place config.toml at workspace root

```bash
mkdir -p /tmp/cryptography/.cargo
cp cargo-config.toml /tmp/cryptography/.cargo/config.toml
```

The config:
- Sets `s390x-ibm-zos-cc` as linker
- Injects `libpython3.12.x` side-deck for PyO3
- Links `libzos_strerror.a` for `__strerror_r_ascii` (needed by OpenSSL 4.0.0)
- Disables s390x SIMD vectorisation
- Sets `rustc-wrapper` to `rustc-wrapper-crypt.sh`

### 3. Copy the rustc wrapper

```bash
cp rustc-wrapper-crypt.sh /home/itodorov/rust_bld/toolchain/
chmod +x /home/itodorov/rust_bld/toolchain/rustc-wrapper-crypt.sh
```

The wrapper injects `--extern` flags for proc-macro crates (`asn1_derive`,
`openssl_macros`, `pyo3_macros`) when compiling for the s390x target.  This is
needed because `asn1` does `pub use asn1_derive::oid;` which requires the
proc-macro to be resolvable as an `--extern` even in target builds.

### 4. Build

```bash
export CC_s390x_ibm_zos=$TOOLCHAIN/s390x-ibm-zos-cc
export AR_s390x_ibm_zos=$TOOLCHAIN/s390x-ibm-zos-ar
export CROSS_SERVER_DOMAIN=zoscan2b.pok.stglabs.ibm.com
export CROSS_SERVER_PORT=5051
export CROSS_SERVER_TIMEOUT=7200
export OPENSSL_DIR=/tmp/zos-sysroot/openssl
export OPENSSL_STATIC=1
export OPENSSL_NO_VENDOR=1
export PYO3_CONFIG_FILE=.../cross/patches/pyo3-zos/pyo3-zos-config.txt
export PYO3_CROSS_LIB_DIR=/tmp/zos-sysroot/python3.12/lib/python3.12

# First build proc-macros natively for the release profile
cargo build --release -p asn1_derive -p openssl-macros -p pyo3-macros

# Then full cross-compile build
cargo build --release --target s390x-ibm-zos
```

Output: `target/s390x-ibm-zos/release/deps/libcryptography_rust.so` (~67 MB)

### 5. Install on z/OS

```bash
# Tag and make executable
chtag -b _rust.cpython-312.so
chmod +x _rust.cpython-312.so

# Set LIBPATH for libzoslib
export LIBPATH=/home/itodoro/zopen/usr/local/lib:$LIBPATH
```

## Key findings

### `__strerror_r_ascii` unresolved symbol

OpenSSL 4.0.0 (as built by zopencommunity) calls `__strerror_r_ascii()` for
ASCII-mode error string conversion.  This symbol is defined in `libzoslib.a`
(a C++ library), **not** in the IBM LE system libraries.

Linking against `libzoslib.a` drags in C++ runtime symbols (`_ZSt9terminatev`,
`__cxa_guard_release`) which then require the ibm-clang C++ runtime side-decks
(only added when linking as C++, not C).

**Solution**: provide a minimal pure-C stub `zos_strerror_stub.c` that
implements `__strerror_r_ascii` using `strerror()` + `__e2a_l()`.  This avoids
the C++ runtime dependency entirely.

### Proc-macro `pub use` re-export pattern

The `asn1` crate does:
```rust
pub use asn1_derive::{oid, Asn1DefinedByRead, ...};
```

When Cargo cross-compiles `asn1` for `s390x-ibm-zos`, it does NOT automatically
pass `--extern asn1_derive=<host.so>` even though it compiled `asn1_derive` for
the host.  The rustc-wrapper intercepts these compilations and adds the missing
`--extern` flags pointing at the proc-macro `.so` files that Cargo already built
in `target/release/deps/`.

### Dynamic vs static libzoslib

`libzoslib.a` is a static archive but its members import from `libzoslib.so` at
runtime (z/OS DLL mechanism).  The `.so` therefore requires `libzoslib.so` in
`LIBPATH` at runtime.  The minimal `libzos_strerror.a` stub avoids this.
