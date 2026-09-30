# Joining Machine Daemon — public recipe

This repository contains the portable, open-source MIDI-CI responder and
restart-safe daemon core used by a Fountain Coach joining machine.

It is intentionally **not** a credential, FountainStore, identity-enrollment,
deployment, or production-publication repository. A sensitive host supplies
already-admitted identity/readiness bytes and a transport through the typed
interfaces in the package. The host-owned adapter remains responsible for
Store access, signing, target binding, lifecycle policy, and authorization.

## What is transparent

The recipe is reproducible from these immutable inputs:

- this repository at an exact commit or signed release;
- Swift 6.1 or newer;
- the public `Fountain-Coach/midi2` repository at revision
  `08fe3d2a02d10e7737b0c533ece583b08397c67b`;
- the committed `Package.swift` and SwiftPM resolution;
- the source and build checks below.

Fetch without executing repository-provided code:

```sh
git clone https://github.com/Fountain-Coach/joining-machine-daemon.git
cd joining-machine-daemon
git checkout --detach <EXACT_COMMIT>
git diff --exit-code
swift package resolve
swift package show-dependencies
```

The command above is an inspection step. Review the exact commit, manifest,
dependency revision, license, and source before building. Do not pipe fetched
content to a shell or install a fetched binary.

## Build and test

```sh
swift build --product joining-machine-daemon -c release
swift test
```

The public package produces a library and a reference `joining-machine-daemon`
Linux/macOS executable. Live mode accepts typed MUID, software revision,
endpoint, and an absolute target-owned readiness-file path. The daemon does
not manufacture a machine identity, read a Store, access a keychain, or
install itself. Base64 readiness input is retained only for explicit
`--self-test` codec checks and is rejected for live mode. A realm-specific
host adapter must create or reuse identity, write and read back the Store
readiness projection, and preserve its own native authorization proof.

## Sensitive-realm boundary

The public recipe never contains:

- Store paths, Store receipts, readiness secrets, signing keys, or credentials;
- private EstatePublisher source or deployment targets;
- host-specific addresses, service units, or production configuration.

The private EstatePublisher integration must consume an exact public revision,
verify the clean checkout and dependency lock, build the
`joining-machine-daemon` product as a Linux ELF artifact,
record source/artifact digests and provenance, and only then perform the
existing native installation/admission operation. Public source transparency
does not by itself prove target admission or production safety.

## Provenance

The public protocol dependency is independently maintained at
<https://github.com/Fountain-Coach/midi2>. The private Store/identity adapter
is deliberately not mirrored here. Changes to either boundary require a new
reviewed revision and a new release manifest; mutable branch names are not
release identities.
