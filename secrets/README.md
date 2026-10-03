# secrets/

Every file here is encrypted with SOPS (age). Keys stay readable, values do not,
so a diff shows *which* setting changed without showing the value.

- Edit: `sops secrets/<file>.yaml` (decrypts into your editor, re-encrypts on save)
- Never write a decrypted copy into this directory.
- Recipients and key locations: `.sops.yaml` and `docs/design/IAC-DESIGN.md`.
