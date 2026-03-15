#!/usr/bin/env python3
"""Estimate the lightweight Docker Compose stack fit for a single VPS."""

services = [
    ("docker-engine", 120),
    ("apisix-standalone", 220),
    ("shared-stunnel-client", 50),
    ("accounts", 420),
    ("rag-server", 300),
    ("os-buffer", 250),
]

total = sum(mem for _, mem in services)

print("Docker Compose Lite capacity estimate")
for name, mem in services:
    print(f"  - {name}: {mem}Mi")
print()
print(f"Total estimated resident memory: {total}Mi")
print("Target host recommendation:")
print("  - minimum: 2C2G")
print("  - comfortable: 2C4G")

if total <= 1536:
    print("Result: Fits comfortably inside a 2Gi host with careful log control.")
else:
    print("Result: Prefer a 4Gi host.")
