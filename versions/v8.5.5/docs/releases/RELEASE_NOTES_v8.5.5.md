# WINDO v8.5.5 - Bootstrap Handoff Guard

Release date: 2026-05-26

## Summary

WINDO v8.5.5 fixes a bootstrap handoff failure after a verified installer download where the launch wrapper could collide with PowerShell's `ErrorAction` common parameter before UAC completed.

## Fixed

- The bootstrap `Start-WindoBootstrapProcess` wrapper now uses an internal `ProcessErrorAction` parameter name.
- The wrapper still passes `ErrorAction = Stop` to `Start-Process`, preserving fail-fast launch behavior without exposing a duplicate command parameter name.

## Validation

- Bootstrap wrapper launch contract is covered with a local `Start-Process` stub.
- Installer, bootstrap, checksum manifest, and frozen version snapshot validate together.
