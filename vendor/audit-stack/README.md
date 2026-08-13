# Vendored audit-stack

This directory vendors the audit-stack NixOS modules and runtime sensor
sources used by ThornixOS. It is intentionally local so ThornixOS builds do
not depend on an unpublished upstream commit.

Snapshot: local audit-stack commit `372920d`.

When upstream exposes a supported flake module, follow the migration steps in
the ThornixOS README and remove this directory.
