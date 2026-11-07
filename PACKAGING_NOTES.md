# Packaging Notes

This directory is the host-side launcher for the unified reviewer artifact.

Reviewers should start with:

- `README.md` in this directory on the host
- `/home/debian/README.md` after logging into the bundled VM

Current intended guest paths:

- software artifact: `/home/debian/artifact`
- hardware artifact: `/home/debian/hw_artifact/rst-hardware`

The bundled VM already includes both trees and the validated Verilator install used by the
hardware flow. `sync_to_vm.sh` is a maintainer helper and is not part of the normal reviewer path.
