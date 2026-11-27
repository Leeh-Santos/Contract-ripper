#!/usr/bin/env python3
"""Retrieve similar historical findings from the knowledge base (RAG front door).

The detection-agent and exploitation-agent call this to pull the closest known bugs:

    python3 scripts/search_kb.py "erc4626 first depositor donation inflation" -k 5

BM25 ranking over the index built by ingest.py. Stdlib only. If the index is missing,
it builds it first. Swap the internals for a vector DB later; keep this CLI stable so
the agents never change.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = os.path.join(ROOT, "knowledge-base", ".index.json")
TOKEN = re.compile(r"[a-z0-9_]+")

K1, B = 1.5, 0.75


def tokenize(text):
    return TOKEN.findall(text.lower())


def ensure_index():
    if not os.path.exists(INDEX):
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ingest.py")],
                       check=True)


def score(query_tokens, idx):
    docs = idx["docs"]
    avgdl, idf = idx["avgdl"] or 1.0, idx["idf"]
    results = []
    qset = set(query_tokens)
    for d in docs:
        toks = d["tokens"]
        dl = len(toks) or 1
        tf = {}
        for t in toks:
            if t in qset:
                tf[t] = tf.get(t, 0) + 1
        if not tf:
            continue
        s = 0.0
        for t, f in tf.items():
            w = idf.get(t, 0.0)
            s += w * (f * (K1 + 1)) / (f + K1 * (1 - B + B * dl / avgdl))
        results.append((s, d))
    results.sort(key=lambda x: x[0], reverse=True)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query", help="natural-language description of the bug shape")
    ap.add_argument("-k", type=int, default=5, help="number of results")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    ensure_index()
    with open(INDEX, encoding="utf-8") as f:
        idx = json.load(f)

    ranked = score(tokenize(args.query), idx)[: args.k]

    if args.json:
        out = [{"score": round(s, 3), "doc_id": d["doc_id"], "title": d["title"],
                "class": d["class"], "severity": d["severity"], "ref": d["ref"],
                "text": d["text"]} for s, d in ranked]
        print(json.dumps(out, indent=2))
        return

    if not ranked:
        print("no matches. (index has %d chunks — add findings and re-ingest)"
              % idx["N"])
        return
    for s, d in ranked:
        print("── [%.2f] %s  (%s, %s)" % (s, d["title"], d["class"], d["severity"]))
        print("   %s   %s" % (d["doc_id"], d["ref"]))
        snippet = " ".join(d["text"].split())
        print("   " + (snippet[:280] + ("…" if len(snippet) > 280 else "")))
        print()


if __name__ == "__main__":
    main()
