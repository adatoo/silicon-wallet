#!/usr/bin/env python3
"""Full-file decrypt + validate, using the key/IV scheme found by brute.py:
  key = ("W7f@" + password) repeated/truncated to 32 bytes (AES-256)
  IV(page_no) = page_no as little-endian uint32, zero-padded to 16 bytes
  mode: try OFB and CTR (identical on the first block; this disambiguates)
  page 1 bytes 16-23 are never encrypted (left as literal plaintext)
"""
import struct
import sys
import os
import sqlite3
import tempfile

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

FIX = os.path.join(os.path.dirname(__file__), "..", "..", "Fixtures", "AcrylicWallet")
PAGE = 1024


def read(name):
    with open(os.path.join(FIX, name), "rb") as f:
        return f.read()


def repeat_to(data, n):
    out = (data * (n // len(data) + 1))[:n]
    return out


def key_for(password):
    return repeat_to(b"W7f@" + password.encode("utf-8"), 32)


def iv_for(page_no):
    return struct.pack("<I", page_no) + b"\x00" * 12


def decrypt_page(key, page_no, ct_page, mode_name):
    iv = iv_for(page_no)
    if mode_name == "ofb":
        mode = modes.OFB(iv)
    elif mode_name == "ctr":
        mode = modes.CTR(iv)
    elif mode_name == "cbc":
        mode = modes.CBC(iv)
    else:
        raise ValueError(mode_name)
    c = Cipher(algorithms.AES(key), mode)
    d = c.decryptor()
    pt = d.update(ct_page) + d.finalize()
    return pt


def decrypt_file(data, password, mode_name):
    n_pages = len(data) // PAGE
    out = bytearray()
    for i in range(n_pages):
        page_no = i + 1
        ct_page = data[i * PAGE:(i + 1) * PAGE]
        pt_page = bytearray(decrypt_page(key_for(password), page_no, bytes(ct_page), mode_name))
        if page_no == 1:
            # bytes 16-23 are never encrypted; restore the literal ciphertext bytes there
            pt_page[16:24] = ct_page[16:24]
        out += pt_page
    return bytes(out)


def validate(decrypted_bytes):
    with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as f:
        f.write(decrypted_bytes)
        path = f.name
    try:
        con = sqlite3.connect(path)
        cur = con.cursor()
        cur.execute("PRAGMA integrity_check")
        rows = cur.fetchall()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [r[0] for r in cur.fetchall()]
        con.close()
        return rows, tables
    except Exception as e:
        return [(f"EXCEPTION: {e}",)], []
    finally:
        os.unlink(path)


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

if __name__ == "__main__":
    for mode_name in ("ofb", "ctr", "cbc"):
        print(f"=== mode {mode_name} ===")
        for fname, pw in FILES_PW.items():
            data = read(fname)
            pt = decrypt_file(data, pw, mode_name)
            rows, tables = validate(pt)
            ok = rows == [("ok",)]
            print(f"  {fname:14s} integrity={rows} tables={tables if ok else '-'}")
