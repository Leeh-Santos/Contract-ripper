#!/usr/bin/env python3
"""Ingest the knowledge base into a local search index (build artifact).

Reads every knowledge-base/findings/*.md (skips _SCHEMA.md), chunks by section,
builds a BM25-style inverted index, and writes it to knowledge-base/.index.json.

Stdlib only (Python 3.8+), no external services. This is the "ingested once into a
vector store" step from the design, kept dependency-free so it runs anywhere. Swap in
a real embedding store later without changing the agents — they only call search_kb.py.

Usage:
    python3 scripts/ingest.py
Run with -I when the findings come from an untrusted dump:
    python3 -I scripts/ingest.py
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FINDINGS = os.path.join(ROOT, "knowledge-base", "findings")
INDEX = os.path.join(ROOT, "knowledge-base", ".index.json")

TOKEN = re.compile(r"[a-z0-9_]+")


def tokenize(text):
    return TOKEN.findall(text.lower())


def parse_frontmatter(text):
    meta = {}
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            block = text[3:end]
            for line in block.splitlines():
                if ":" in line:
                    k, _, v = line.partition(":")
                    meta[k.strip()] = v.strip().strip('"')
            text = text[end + 4:]
    return meta, text


def chunk(text):
    """One chunk per '## Section'; keep the section title with the body."""
    parts = re.split(r"(?m)^##\s+", text)
    chunks = []
    for p in parts:
        p = p.strip()
        if p:
            chunks.append(p)
    return chunks or [text.strip()]


def main():
    docs = []
    if not os.path.isdir(FINDINGS):
        print("no findings dir:", FINDINGS, file=sys.stderr)
        sys.exit(1)
    for fn in sorted(os.listdir(FINDINGS)):
        if not fn.endswith(".md") or fn.startswith("_"):
            continue
        path = os.path.join(FINDINGS, fn)
        with open(path, encoding="utf-8") as f:
            raw = f.read()
        meta, body = parse_frontmatter(raw)
        for i, ch in enumerate(chunk(body)):
            docs.append({
                "doc_id": "kb://findings/" + fn[:-3],
                "file": fn,
                "chunk": i,
                "title": meta.get("title", fn),
                "class": meta.get("class", ""),
                "severity": meta.get("severity", ""),
                "ref": meta.get("ref", ""),
                "text": ch,
                "tokens": tokenize(meta.get("title", "") + " " +
                                   meta.get("class", "") + " " + ch),
            })

    # BM25 stats
    N = len(docs)
    df = {}
    for d in docs:
        for t in set(d["tokens"]):
            df[t] = df.get(t, 0) + 1
    avgdl = (sum(len(d["tokens"]) for d in docs) / N) if N else 0.0
    idf = {t: math.log(1 + (N - n + 0.5) / (n + 0.5)) for t, n in df.items()}

    index = {
        "version": 1,
        "N": N,
        "avgdl": avgdl,
        "idf": idf,
        "docs": [{k: v for k, v in d.items()} for d in docs],
    }
    with open(INDEX, "w", encoding="utf-8") as f:
        json.dump(index, f)
    print("indexed %d chunks from %d findings -> %s" %
          (N, len({d['file'] for d in docs}), os.path.relpath(INDEX, ROOT)))


if __name__ == "__main__":
    main()
