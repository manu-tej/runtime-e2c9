# Runtime bundle e2c9

This directory contains the public, neutral-name provisioning bundle for the
isolated LTX 2.3 Vast Serverless benchmark. It contains only public model URLs,
pinned node revisions, compatibility code, and a bounded API-format benchmark.
It contains no credentials, prompts supplied by users, reference media, or
generated output.

The Vast endpoint and worker group both have zero active and cold floors, a
single-worker maximum, and a 60-second inactivity timeout. Transient ComfyUI
files are periodically reaped and the scratch worker is deleted after the
benchmark reaches scale-to-zero.

The same bundle also carries `scail2-provision.sh`, the isolated SCAIL-2 FP8
runtime with public adapters, SAM3 support, and a deterministic benchmark that
uses generated in-memory fixtures rather than user media.
