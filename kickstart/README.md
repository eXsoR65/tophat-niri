# Kickstart example

`tophat-minimal.ks.example` is a starting point for a Fedora Minimal install. It
is intentionally not ready to run until you review and replace the required
placeholders.

## Safety requirements

Before using a copy of the example:

- Keep SELinux enforcing.
- Keep the firewall enabled.
- Do not commit plaintext passwords or private password hashes.
- Do not use an empty disk-encryption passphrase.
- Confirm the target disk before uncommenting destructive partitioning lines.
- Leave IPv6 enabled unless you have a documented reason to disable it.

Validate examples with:

```bash
kickstart/validate-kickstart.sh
```

The validator rejects known unsafe public-template defaults and unresolved
placeholders in active Kickstart directives.
