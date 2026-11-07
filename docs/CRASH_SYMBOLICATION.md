# Release diagnostics and crash symbolication

Every release build from **56** collects seven diagnostics archives:
macOS arm64, Linux x86_64, Windows x86_64, and the Linux/macOS helpers for both
x86_64 and arm64. `release/diagnostics-policy.json` records the introduction
boundary. Older releases cannot acquire matching symbols by rebuilding their
source later.

## What is retained

Each archive contains a manifest, the native images from the shipped payload,
matching native symbols where available, Dart split-debug maps, version/build,
source commit, Flutter framework and engine revisions, Dart/Rust toolchain
versions, dependency locks and shared-source pins. The desktop manifests bind
these to the final six installer SHA-256 hashes. macOS collection mounts the
signed/notarized DMG read-only, so it examines the thinned, signed payload.
The Windows bundle has already been signed and packaged; Linux qualification
checks the payload used by all four formats.

Native matching uses **Mach-O UUID per architecture**, **ELF GNU build ID**, or
**PE CodeView/PDB GUID and age**. A filename, version, helper compatibility ID
or source commit alone is insufficient. Fat macOS dSYMs may contain additional
architectures, but every shipped slice must match. The actual dSYM bundle,
including its metadata and DWARF file, is retained. PDB basenames are preserved.

Rust release builds retain limited debug information in their build outputs.
Linux C++ builds retain line tables; Windows release builds produce PDBs while
keeping optimization. Packaging strips debug sections from Linux runtime
copies, and helper packaging strips/signs a copy instead of destroying Cargo's
original. Dart builds use `--split-debug-info` without enabling obfuscation.
Symbols are excluded from the user installers.

First-party symbols and the macOS/Windows Flutter engine symbols are required.
The pinned Linux Flutter SDK does not supply engine DWARF. Its exact stripped
image, build ID and engine revision are retained, and the index explicitly
records this vendor gap. Missing Sparkle or Microsoft runtime symbols are also
recorded as vendor gaps, never as successful symbol coverage. Locally built
plugins are required to have matching symbols. A future matching vendor symbol
file can be associated by native identity; an unrelated debug engine cannot
symbolicate the shipped engine. This workflow does not build a custom Flutter
engine or promise that every vendor frame has a source line.

## Collection and retention

`scripts/collect-debug-symbols.py` collects one unit from its build/payload.
Target jobs upload five CI handoffs: three desktop jobs and two helper jobs
(each helper job supplies two architectures).

Before publication, `scripts/retain-debug-symbols.py` verifies the complete
seven-unit set, all native symbol identities, dependency/toolchain consistency,
Dart map presence, bundled-helper identities and final installer digests. It
writes an immutable snapshot:

```text
diagnostics/vVERSION-BUILD/<archive-set-sha256>/
  index.json
  GitLama-VERSION-BUILD-UNIT-diagnostics.tar.gz
```

The release workflow keeps that snapshot as the workflow artifact
`gitlama-private-diagnostics-vVERSION-BUILD` for 90 days. Download it from the
release run and keep it with your own backups if crashes of that build must stay
symbolicatable after the artifact expires; this code does not keep a copy
elsewhere. Workflow artifacts are readable by everyone who can read the
repository. The archives contain symbols of open source code built on
GitHub-hosted runners, so they name only runner paths, but keep crash reports
themselves private. The six-package signed update manifest and the public
release assets never include diagnostics.

The archive verifier refuses unsafe members, digest mismatches, more than
10,000 members or more than 4 GiB of unpacked content per archive. That is an
ingestion budget, not a claim about the hosting service's upload ceiling.

For a local development packaging rehearsal, set
`GITLAMA_COLLECT_DIAGNOSTICS=1` on the target packaging step. The release
workflow enables it automatically. Dirty-tree or glibc-floor
bypass rehearsals are marked as development diagnostics, which the release
collection gate refuses. Never publish those packages as release candidates.

## Investigate a crash

1. Obtain the complete `.ips` or `.crash` report, including **Binary Images**
   (or `usedImages`), the faulting thread, image load addresses, architecture,
   version and build. The report can contain user data; keep it private.
2. Locate the release snapshot by version/build and installer digest, then match
   the crashing image's native identity. For helpers, also obtain the helper's
   `--version` source commit: the compatibility ID can span multiple releases.
3. Verify/list the relevant archive and extract it into a new private directory:

   ```bash
   python3 scripts/inspect-debug-symbols.py ARCHIVE --image FlutterMacOS
   python3 scripts/inspect-debug-symbols.py ARCHIVE --extract private-symbols
   ```

   The inspector validates inventory digests and native symbol matches before
   extraction and refuses an existing destination. Read `manifest.json` for
   `symbol_file`, `identity`, `coverage` and the recorded binary path. A vendor
   gap is explicit; no matching debug file is manufactured for it.

4. On macOS, open the complete crash report in Xcode with the extracted dSYMs
   available, or resolve individual frames using the manifest's DWARF file:

   ```bash
   atos -arch arm64 -o path/to/dSYM/Contents/Resources/DWARF/FlutterMacOS \
     -l IMAGE_LOAD_ADDRESS FRAME_ADDRESS
   ```

   Confirm `dwarfdump --uuid` matches the report first.

5. On Linux, pass a module-relative address to the retained `.debug` file:

   ```bash
   addr2line -C -f -i -e path/to/symbols/0.debug MODULE_RELATIVE_ADDRESS
   ```

   Preserve the original core and module mappings privately when available;
   ASLR means an absolute address needs the module's load bias accounted for.

6. On Windows, open the dump in WinDbg, add the recorded PDB directory to
   `.sympath`, run `.reload /f`, and inspect the stack. Match both GUID and age;
   copying a newly compiled PDB under the expected filename does not make it
   compatible. Use the archived image if the debugger also needs its PE image.

7. For a Dart AOT stack, use the matching target's retained map:

   ```bash
   flutter symbolize --input dart-stack.txt --debug-info path/to/app.TARGET.symbols
   ```

   OS native frames and Dart stack traces use different symbolication paths.

Apple documents [binary/dSYM UUID matching](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file)
and [native frame symbolication](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report).
Rust documents [release debug information and stripping](https://doc.rust-lang.org/cargo/reference/profiles.html#debug).
