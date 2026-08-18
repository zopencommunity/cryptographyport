#!/usr/bin/env python3
"""
cryptography z/OS smoke tests.

Run on z/OS with:
  export _BPXK_AUTOCVT=ON
  export LIBPATH=~/zopen/usr/local/lib:$LIBPATH
  python3 test_cryptography_zos.py
"""
import sys

def test_version():
    import cryptography
    assert cryptography.__version__, "version string empty"
    print(f"  version: {cryptography.__version__}")

def test_sha256():
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.backends import default_backend
    digest = hashes.Hash(hashes.SHA256(), backend=default_backend())
    digest.update(b"hello z/OS")
    result = digest.finalize()
    expected = "6dc1a19e0cb5f3f43c310e992f8a276fb884d826639af9f6f6b8c3fbbba038e2"
    assert result.hex() == expected, f"SHA256 mismatch: {result.hex()}"
    print(f"  SHA256: {result.hex()}")

def test_aes_cbc():
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    import os
    key = os.urandom(32)
    iv = os.urandom(16)
    plaintext = b"0123456789abcdef"  # exactly 16 bytes
    c = Cipher(algorithms.AES(key), modes.CBC(iv))
    enc = c.encryptor()
    ct = enc.update(plaintext) + enc.finalize()
    dec = c.decryptor()
    pt = dec.update(ct) + dec.finalize()
    assert pt == plaintext, "AES-CBC round-trip failed"
    print(f"  AES-256-CBC: {len(ct)} bytes ciphertext, round-trip OK")

def test_rsa():
    from cryptography.hazmat.primitives.asymmetric import rsa, padding
    from cryptography.hazmat.primitives import hashes
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    msg = b"Test message from z/OS"
    sig = key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
    key.public_key().verify(sig, msg, padding.PKCS1v15(), hashes.SHA256())
    print(f"  RSA-2048 sign/verify: OK ({len(sig)} byte signature)")

def test_ecdsa():
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import hashes
    key = ec.generate_private_key(ec.SECP256R1())
    msg = b"z/OS ECDSA test"
    sig = key.sign(msg, ec.ECDSA(hashes.SHA256()))
    key.public_key().verify(sig, msg, ec.ECDSA(hashes.SHA256()))
    print(f"  ECDSA P-256 sign/verify: OK ({len(sig)} byte signature)")

def test_x509():
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import hashes, serialization
    import datetime
    key = ec.generate_private_key(ec.SECP256R1())
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "z/OS test")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=365))
        .sign(key, hashes.SHA256())
    )
    pem = cert.public_bytes(serialization.Encoding.PEM)
    cn = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    assert cn == "z/OS test"
    assert pem.startswith(b"-----BEGIN CERTIFICATE-----")
    print(f"  X.509 self-signed cert: {len(pem)} bytes, CN={cn}")

def test_fernet():
    from cryptography.fernet import Fernet
    key = Fernet.generate_key()
    f = Fernet(key)
    plaintext = b"secret z/OS data"
    token = f.encrypt(plaintext)
    decrypted = f.decrypt(token)
    assert decrypted == plaintext, "Fernet round-trip failed"
    print(f"  Fernet: token={len(token)} bytes, round-trip OK")

def test_hmac():
    from cryptography.hazmat.primitives import hmac, hashes
    import os
    key = os.urandom(32)
    h = hmac.HMAC(key, hashes.SHA256())
    h.update(b"z/OS HMAC test")
    sig = h.finalize()
    assert len(sig) == 32
    print(f"  HMAC-SHA256: {sig.hex()[:16]}...")

TESTS = [
    ("version",  test_version),
    ("SHA-256",  test_sha256),
    ("AES-256-CBC", test_aes_cbc),
    ("RSA-2048", test_rsa),
    ("ECDSA P-256", test_ecdsa),
    ("X.509",    test_x509),
    ("Fernet",   test_fernet),
    ("HMAC-SHA256", test_hmac),
]

passed = failed = 0
for name, fn in TESTS:
    try:
        print(f"[{name}]")
        fn()
        passed += 1
    except Exception as e:
        print(f"  FAILED: {e}", file=sys.stderr)
        failed += 1

print(f"\n{passed}/{passed+failed} tests passed", end="")
if failed:
    print(f"  ({failed} FAILED)", file=sys.stderr)
    sys.exit(1)
else:
    print(" — ALL OK")
