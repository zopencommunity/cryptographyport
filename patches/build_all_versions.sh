#!/usr/bin/env bash
# Build cryptography 50.0.0 wheels for z/OS (all three Python versions)
# Must be run from /tmp/cryptography on the LoP cross-compile machine.
set -euo pipefail

TOOLCHAIN=/home/itodorov/rust_bld/toolchain
SYSROOT=/home/itodoro/rust_bld/rustcross/sysroot/lib
PATCHES=/home/itodorov/rust-scripts/cross/patches
SCRIPTS=/home/itodorov/rust-scripts/cross

export PATH="/gsa/rtpgsa/projects/r/rustcross/v186/lop/rustcross/260610/usr/local/bin:$PATH"
export CC_s390x_ibm_zos=$TOOLCHAIN/s390x-ibm-zos-cc
export AR_s390x_ibm_zos=$TOOLCHAIN/s390x-ibm-zos-ar
export CROSS_SERVER_DOMAIN=zoscan2b.pok.stglabs.ibm.com
export CROSS_SERVER_PORT=5051
export CROSS_SERVER_TIMEOUT=7200
export OPENSSL_DIR=/tmp/zos-sysroot/openssl
export OPENSSL_STATIC=1
export OPENSSL_NO_VENDOR=1

OUT=/tmp/wheels-release
mkdir -p "$OUT"

build_version() {
  local PYVER=$1       # e.g. 3.12
  local PYTAG=$2       # e.g. cp312
  local PYLIB=$3       # e.g. /usr/lpp/IBM/.../libpython3.12.x
  local PYO3_CFG=$4    # path to pyo3-zos-config.txt
  local PYO3_LIB=$5    # path to python lib dir

  echo ""
  echo "=== Building $PYTAG ==="

  cat > .cargo/config.toml << TOML
[build]
rustc-wrapper = "${TOOLCHAIN}/rustc-wrapper-crypt.sh"
[target.s390x-ibm-zos]
linker = "${TOOLCHAIN}/s390x-ibm-zos-cc"
rustflags = [
  "-C", "link-arg=${PYLIB}",
  "-C", "link-arg=${SYSROOT}/libzoslib.a",
  "-C", "link-arg=${SYSROOT}/libzoslib-supp.a",
  "-C", "link-arg=${SYSROOT}/libssl.a",
  "-C", "link-arg=${SYSROOT}/libcrypto.a",
  "-C", "link-arg=${SYSROOT}/libzos_strerror.a",
  "-C", "target-feature=-vector",
]
TOML

  rm -f target/s390x-ibm-zos/release/deps/lib_rust.so
  cargo clean --target s390x-ibm-zos --release 2>/dev/null || true
  PYO3_CONFIG_FILE="$PYO3_CFG" \
  PYO3_CROSS_LIB_DIR="$PYO3_LIB" \
  cargo build --release --target s390x-ibm-zos 2>&1 | grep -E "Finished|^error"

  python3 "$SCRIPTS/build_cryptography_wheel.py" \
    --so target/s390x-ibm-zos/release/deps/lib_rust.so \
    --pyver "$PYVER" --pytag "$PYTAG" \
    --src src/cryptography --version 50.0.0 \
    --out "$OUT"
}

build_version 3.12 cp312 \
  /usr/lpp/IBM/cyp/v3r12/pyz/lib/libpython3.12.x \
  "$PATCHES/pyo3-zos/pyo3-zos-config.txt" \
  /tmp/zos-sysroot/python3.12/lib/python3.12

build_version 3.13 cp313 \
  "${SYSROOT}/libpython3.13.x" \
  "$PATCHES/pyo3-zos/pyo3-zos-config-3.13.txt" \
  /tmp/zos-sysroot/python3.13/lib/python3.13

build_version 3.14 cp314 \
  "${SYSROOT}/libpython3.14.x" \
  "$PATCHES/pyo3-zos/pyo3-zos-config-3.14.txt" \
  /tmp/zos-sysroot/python3.14/lib/python3.14

echo ""
echo "=== Wheels ==="
ls -lh "$OUT"/cryptography-50.0.0-*.whl
