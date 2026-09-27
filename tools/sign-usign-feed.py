#!/usr/bin/env python3
"""Sign an OpenWrt Packages index with an existing, unencrypted usign key.

The private key is read locally and never copied into the feed or VM. The
signature is standard usign Ed25519 and should be verified by OpenWrt usign.
"""

import argparse
import base64
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives import serialization


def payload(path: Path) -> bytes:
    lines = path.read_text(encoding="ascii").splitlines()
    if len(lines) < 2 or not lines[0].startswith("untrusted comment: "):
        raise ValueError(f"Malformed usign file: {path}")
    return base64.b64decode(lines[1], validate=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--secret", type=Path, required=True)
    parser.add_argument("--public", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--signature", type=Path, required=True)
    args = parser.parse_args()

    secret = payload(args.secret)
    public = payload(args.public)
    if len(secret) != 104 or secret[:4] != b"EdBK" or int.from_bytes(secret[4:8], "little") != 0:
        raise ValueError("Expected an unencrypted Ed25519 usign secret key")
    if len(public) != 42 or public[:2] != b"Ed":
        raise ValueError("Expected an Ed25519 usign public key")
    fingerprint, seed, embedded_public = secret[32:40], secret[40:72], secret[72:104]
    if fingerprint != public[2:10]:
        raise ValueError("Signing key fingerprint differs from public key")
    private = Ed25519PrivateKey.from_private_bytes(seed)
    derived_public = private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    if embedded_public != public[10:42] or derived_public != public[10:42]:
        raise ValueError("Signing key does not match the pinned public key")

    signature = private.sign(args.index.read_bytes())
    Ed25519PublicKey.from_public_bytes(public[10:42]).verify(signature, args.index.read_bytes())
    blob = b"Ed" + fingerprint + signature
    args.signature.write_text(
        f"untrusted comment: signed by key {fingerprint.hex()}\n"
        f"{base64.b64encode(blob).decode('ascii')}\n",
        encoding="ascii", newline="\n",
    )
    print(f"Signed {args.index.name} with key {fingerprint.hex()}")


if __name__ == "__main__":
    main()
