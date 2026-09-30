# Provenance and reproducibility

The public source is intended to be fetched and reviewed before execution.
Every release must identify:

- the exact public repository commit;
- the exact `Package.swift` and committed `Package.resolved`;
- the exact `Fountain-Coach/midi2` revision;
- the Swift toolchain and target platform;
- source archive and built-artifact SHA-256 digests;
- the signed release manifest, when a release is used.

The current dependency pin is:

`https://github.com/Fountain-Coach/midi2.git`

`08fe3d2a02d10e7737b0c533ece583b08397c67b`

The package deliberately has no binary download path. The supported default
is source fetch, detached exact revision, dependency resolution, local review,
and local build. Any consuming EstatePublisher release must preserve this
provenance tuple in its native release receipt.
