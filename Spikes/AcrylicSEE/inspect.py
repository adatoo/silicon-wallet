#!/usr/bin/env python3
"""Dump decrypted table contents for a vault, to sanity-check against README.md/NOTES.md."""
import sys
import os
import sqlite3
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from decrypt import read, decrypt_file, FILES_PW  # noqa: E402

fname = sys.argv[1] if len(sys.argv) > 1 else "a.wallet"
pw = FILES_PW[fname]
data = read(fname)
pt = decrypt_file(data, pw, "ofb")

with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as f:
    f.write(pt)
    path = f.name

con = sqlite3.connect(path)
cur = con.cursor()
for t in ("groups", "entries", "files", "logs", "deleted"):
    try:
        cur.execute(f"PRAGMA table_info({t})")
        cols = [r[1] for r in cur.fetchall()]
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        count = cur.fetchone()[0]
        print(f"{t}: {count} rows, columns={cols}")
    except Exception as e:
        print(f"{t}: ERROR {e}")
print()
cur.execute("SELECT * FROM groups")
for row in cur.fetchall():
    print("group:", row)
print()
cur.execute("SELECT * FROM entries")
for row in cur.fetchall():
    print("entry:", row)
con.close()
os.unlink(path)
