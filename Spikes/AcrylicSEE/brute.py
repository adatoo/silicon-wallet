#!/usr/bin/env python3
"""Black-box SEE key/cipher search against the fake Acrylic Wallet fixtures.

Test-only spike code (DESIGN.md §9). Never run against a real vault.
Uses only the known 16-byte plaintext "SQLite format 3\\0" at offset 0 of
page 1, plus full-file SQLite integrity checks to confirm any hit.
"""
import hashlib
import os
import struct
import sys
import sqlite3
import tempfile
import unicodedata

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

FIX = os.path.join(os.path.dirname(__file__), "..", "..", "Fixtures", "AcrylicWallet")
PAGE = 1024
KNOWN_PT = b"SQLite format 3\x00"

FILES_PW = {
    "a.wallet": "fakepass",
    "b.wallet": "fakepass",
    "g.wallet": "fakepass",
    "c.wallet": "fakepass1234",
    "d.wallet": "fakepass12XY",
    "e.wallet": "fakepass-fakepass-fakepass-fakepass-1234",
    "f.wallet": "fake-p\u00e4ssw\u00f6rd-\u2713",
    "h.wallet": "fakepass-2",
    "i.wallet": "fakepassword",
}


def read(name):
    with open(os.path.join(FIX, name), "rb") as f:
        return f.read()


def pw_byte_variants(pw):
    """Candidate byte encodings of a password string."""
    out = {}
    out["utf8"] = pw.encode("utf-8")
    out["nfc"] = unicodedata.normalize("NFC", pw).encode("utf-8")
    out["nfd"] = unicodedata.normalize("NFD", pw).encode("utf-8")
    out["utf16le"] = pw.encode("utf-16-le")
    try:
        out["latin1"] = pw.encode("latin-1")
    except UnicodeEncodeError:
        pass
    # de-dup
    seen = {}
    for k, v in out.items():
        seen.setdefault(v, k)
    return {name: b for b, name in seen.items()}


PREFIXES = ["", "aes128:", "aes256:", "rc4:", "W7f@"]


def repeat_to(data, n):
    if not data:
        return b"\x00" * n
    out = (data * (n // len(data) + 1))[:n]
    return out


def evp_bytes_to_key_md5(password, salt, key_len):
    d = b""
    prev = b""
    while len(d) < key_len:
        prev = hashlib.md5(prev + password + salt).digest()
        d += prev
    return d[:key_len]


def candidate_keys(pw):
    """Yield (label, key_bytes) for every KDF/password-variant hypothesis."""
    variants = pw_byte_variants(pw)

    for vname, raw in variants.items():
        for prefix in PREFIXES:
            pdata = prefix.encode("utf-8") + raw if prefix != "W7f@" else b"W7f@" + raw
            # 1. raw-repeat ("-key" method)
            for n in (16, 32, 256):
                yield (f"raw-repeat/{vname}/{prefix or '-'}/{n}", repeat_to(pdata, n))
            # 2. single hash, truncated/repeated ("-textkey" method)
            for halg in ("md5", "sha1", "sha256", "sha512"):
                dig = hashlib.new(halg, pdata).digest()
                for n in (16, 32):
                    yield (f"hash-{halg}/{vname}/{prefix or '-'}/{n}", repeat_to(dig, n))
            # 3. EVP_BytesToKey (openssl legacy, MD5, no salt)
            for n in (16, 32):
                yield (f"evp_bytestokey/{vname}/{prefix or '-'}/{n}", evp_bytes_to_key_md5(pdata, b"", n))
            # 4. PBKDF2-HMAC
            for halg, hobj in (("sha1", hashes.SHA1()), ("sha256", hashes.SHA256())):
                for salt_name, salt in (
                    ("empty", b""),
                    ("salt", b"salt"),
                    ("W7f@", b"W7f@"),
                    ("pw", raw),
                    ("zero8", b"\x00" * 8),
                ):
                    for iters in (1, 1000, 2000, 4000, 10000):
                        for n in (16, 32):
                            try:
                                kdf = PBKDF2HMAC(algorithm=hobj, length=n, salt=salt, iterations=iters)
                                key = kdf.derive(pdata)
                            except Exception:
                                continue
                            yield (f"pbkdf2-{halg}/{vname}/{prefix or '-'}/salt={salt_name}/i={iters}/{n}", key)


def iv_candidates(page_no):
    n = page_no
    be4 = struct.pack(">I", n)
    le4 = struct.pack("<I", n)
    be8 = struct.pack(">Q", n)
    le8 = struct.pack("<Q", n)
    cands = {
        "zero": b"\x00" * 16,
        "be4-start": (be4 + b"\x00" * 12),
        "le4-start": (le4 + b"\x00" * 12),
        "be4-end": (b"\x00" * 12 + be4),
        "le4-end": (b"\x00" * 12 + le4),
        "be8-start": (be8 + b"\x00" * 8),
        "le8-start": (le8 + b"\x00" * 8),
        "be8-end": (b"\x00" * 8 + be8),
        "le8-end": (b"\x00" * 8 + le8),
    }
    if 0 <= n < 256:
        cands["byte-repeat"] = bytes([n]) * 16
    return cands


def aes_ecb_block_decrypt(key, block):
    c = Cipher(algorithms.AES(key), modes.ECB())
    d = c.decryptor()
    return d.update(block) + d.finalize()


def aes_ecb_block_encrypt(key, block):
    c = Cipher(algorithms.AES(key), modes.ECB())
    e = c.encryptor()
    return e.update(block) + e.finalize()


def try_first_block(key, ct16, page_no):
    """Try every cipher/mode/IV against one 16-byte known-plaintext block.
    Yields (label, mode_name, iv_label) on a match.
    """
    klen = len(key)
    if klen not in (16, 24, 32):
        return
    # ECB: no IV
    try:
        pt = aes_ecb_block_decrypt(key, ct16)
        if pt == KNOWN_PT:
            yield ("aes-ecb", None)
    except Exception:
        pass
    # OFB / CTR / CBC: keystream0 = AES_Encrypt(key, IV); for CBC first block decrypt = AES_Decrypt(ct) XOR IV
    for iv_label, iv in iv_candidates(page_no).items():
        try:
            ks = aes_ecb_block_encrypt(key, iv)
            pt_ofb = bytes(a ^ b for a, b in zip(ct16, ks))
            if pt_ofb == KNOWN_PT:
                yield ("aes-ofb", iv_label)
            # CTR first block is identical math to OFB for the first block
            if pt_ofb == KNOWN_PT:
                yield ("aes-ctr", iv_label)
        except Exception:
            pass
        try:
            dec = aes_ecb_block_decrypt(key, ct16)
            pt_cbc = bytes(a ^ b for a, b in zip(dec, iv))
            if pt_cbc == KNOWN_PT:
                yield ("aes-cbc", iv_label)
        except Exception:
            pass
    # RC4
    for rc4_label, rc4_key in (
        ("plain", key),
        ("key+pageBE4", key + struct.pack(">I", page_no)),
        ("key+pageLE4", key + struct.pack("<I", page_no)),
        ("pageBE4+key", struct.pack(">I", page_no) + key),
    ):
        try:
            c = Cipher(algorithms.ARC4(rc4_key), mode=None)
            d = c.decryptor()
            pt = d.update(ct16)
            if pt == KNOWN_PT:
                yield (f"rc4/{rc4_label}", None)
        except Exception:
            pass


def search():
    hits = []
    for fname, pw in FILES_PW.items():
        data = read(fname)
        ct16 = data[0:16]
        for label, key in candidate_keys(pw):
            for mode_name, iv_label in try_first_block(key, ct16, 1):
                hits.append((fname, pw, label, mode_name, iv_label, key.hex()))
    return hits


if __name__ == "__main__":
    hits = search()
    if not hits:
        print("NO HITS across the full matrix")
        sys.exit(1)
    print(f"{len(hits)} first-block hit(s):")
    for h in hits:
        print(h)
