#!/bin/bash
# rustc-wrapper-crypt.sh — wrapper for cryptography cross-compilation.
#
# Cargo invokes: rustc-wrapper-crypt.sh <real-rustc> <rustc-args...>
#
# Injects --extern proc-macro flags for s390x-ibm-zos compilations so that
# crates which re-export proc-macro items (pub use asn1_derive::oid; etc.)
# can resolve them. Cargo 1.86 does not pass proc-macro --extern to
# target-side compilations automatically.

RUSTC="$1"; shift

# Only act for z/OS target compilations
is_zos=0
for arg in "$@"; do
    [ "$arg" = "s390x-ibm-zos" ] && is_zos=1 && break
done

if [ "$is_zos" = "0" ]; then
    exec "$RUSTC" "$@"
fi

# Derive host release/deps from --out-dir
# out-dir example: /tmp/cryptography/target/s390x-ibm-zos/release/deps
# host deps:       /tmp/cryptography/target/release/deps
release_deps=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "--out-dir" ]; then
        # Go up: deps -> release -> s390x-ibm-zos -> target
        d1=$(dirname "$arg")        # release
        d2=$(dirname "$d1")         # s390x-ibm-zos
        d3=$(dirname "$d2")         # target
        release_deps="$d3/release/deps"
        break
    fi
    prev="$arg"
done

find_so() {
    local name="$1"
    if [ -n "$release_deps" ] && [ -d "$release_deps" ]; then
        ls -t "$release_deps/lib${name}-"*.so 2>/dev/null | head -1
    fi
}

# Check which proc-macros are already in the arg list
has_asn1=0; has_openssl=0; has_pyo3=0
for arg in "$@"; do
    case "$arg" in
        *asn1_derive=*)    has_asn1=1 ;;
        *openssl_macros=*) has_openssl=1 ;;
        *pyo3_macros=*)    has_pyo3=1 ;;
    esac
done

extra=()
if [ "$has_asn1" = "0" ]; then
    so=$(find_so "asn1_derive")
    [ -n "$so" ] && extra+=("--extern" "asn1_derive=$so")
fi
if [ "$has_openssl" = "0" ]; then
    so=$(find_so "openssl_macros")
    [ -n "$so" ] && extra+=("--extern" "openssl_macros=$so")
fi
if [ "$has_pyo3" = "0" ]; then
    so=$(find_so "pyo3_macros")
    [ -n "$so" ] && extra+=("--extern" "pyo3_macros=$so")
fi

# Debug log (remove when stable)
echo "WRAPPER: release_deps=$release_deps extra_count=${#extra[@]} args=${extra[*]}" \
     >> /tmp/wrapper_crypt.log 2>/dev/null

exec "$RUSTC" "$@" "${extra[@]}"
