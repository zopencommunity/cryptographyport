# cryptographyport

z/OS port of [cryptography](https://github.com/pypa/cryptography) — a Python
package providing cryptographic recipes and primitives using an OpenSSL backend.

## Overview

This port provides `cryptography` for IBM z/OS (Python 3.12), built with:
- **OpenSSL 4.0.0** from [zopencommunity/opensslport](https://github.com/zopencommunity/opensslport) (static linkage)
- **Rust** Rust extension compiled via cross-compilation from Linux-on-Power
- **cffi** for the OpenSSL C bindings (pre-installed with IBM Open Enterprise Python 3.12)

## Prerequisites

- Python 3.12 (`/usr/lpp/IBM/cyp/v3r12/pyz/`)
- [zopencommunity tools](https://github.com/zopencommunity/meta) installed at `~/zopen/`
- `zoslib` (from zopencommunity) — provides ASCII-mode runtime extensions

## Usage

```bash
export LIBPATH=~/zopen/usr/local/lib:$LIBPATH
export _BPXK_AUTOCVT=ON

python3 -c "
from cryptography.hazmat.primitives.asymmetric import rsa, ec
from cryptography.hazmat.primitives import hashes
from cryptography.fernet import Fernet

# AES-256 symmetric encryption
fernet_key = Fernet.generate_key()
f = Fernet(fernet_key)
token = f.encrypt(b'Hello z/OS!')
print(f.decrypt(token))  # b'Hello z/OS!'

# ECDSA P-256 signing
key = ec.generate_private_key(ec.SECP256R1())
sig = key.sign(b'data', ec.ECDSA(hashes.SHA256()))
key.public_key().verify(sig, b'data', ec.ECDSA(hashes.SHA256()))
print('All crypto operations successful')
"
```

## Build

Cross-compiled from Linux-on-Power using the HTTP cross-compile server in
[compiler/rust-scripts](https://github.ibm.com/compiler/rust-scripts).

Patches are in [`patches/`](patches/) — see [`patches/README.md`](patches/README.md)
for detailed explanations of each change and full build instructions.

### Quick build overview

```bash
# 1. Apply patches to cryptography source
git clone https://github.com/pypa/cryptography && cd cryptography
git apply ../patches/cryptography/0001-zos-cargo-patches.patch
mkdir -p .cargo && cp ../patches/cryptography/0002-zos-cargo-config.patch .cargo/config.toml  # see patch for exact content

# 2. Build libzos_strerror.a on z/OS from the stub
# (see patches/README.md for ibm-clang compile command)

# 3. Set up cross-compile environment and build
export OPENSSL_DIR=/path/to/zos-sysroot/openssl
export OPENSSL_STATIC=1
export PYO3_CONFIG_FILE=.../pyo3-zos-config.txt
cargo build --release --target s390x-ibm-zos
```

See `cross/patches/cryptography-zos/` in rust-scripts for the sysroot setup
and pyo3-zos-config.txt.

## CVE Fixes

This port replaces the bundled OpenSSL 3.3.2 (with 22+ CVEs) in the
pre-installed `cryptography 3.3.2` on IBM Open Enterprise Python 3.12 with
OpenSSL 4.0.0.

## License

Apache-2.0 OR BSD-3-Clause
