# Security Policy

## Supported versions

Only the latest tagged release is actively supported. Older releases do not
receive backports.

## Reporting a vulnerability

If you find a security issue — a crash or memory-safety problem triggered by
a malicious subtitle file, a path-traversal in how output filenames are
built, or anything that could leak data from a user's machine — please
**don't open a public GitHub issue.**

Email **jeff.alldridge@gmail.com** with:

- A description of the issue
- Steps to reproduce, ideally with a minimal file that triggers it
- Your suggested severity rating

Expect a response within a few days. Once the issue is fixed and released,
you'll be credited in the changelog unless you'd rather stay anonymous.

## Scope

The app runs entirely on your Mac. It makes exactly one network request: an
optional once-a-day check of the project's GitHub releases for a newer
version number, which you can turn off in Settings. It downloads and installs
nothing on its own.

Since 1.0 the app parses container and subtitle formats itself rather than
shelling out to other tools, so **parsing untrusted files is the main attack
surface**:

- Matroska (`.mkv`, `.mks`) container parsing — EBML elements, cluster and
  block headers, all three lacing modes
- Blu-ray PGS (`.sup`) segment parsing and run-length decoding
- DVD VobSub (`.sub` / `.idx`) MPEG program-stream parsing, control
  sequences, and run-length decoding
- Bitmap composition and palette handling
- File-system writes to the output folder you choose

All of it is memory-safe Swift over a memory-mapped buffer, with bounds
checks on every read, and is written to survive truncated and malformed
input by reporting a problem rather than trapping. A crash, a hang, or a read
past the end of a buffer in any of it is a bug worth reporting.

Not in scope:

- Recognition accuracy. Wrong text is a quality issue; open a normal issue.
- Apple's Vision, Translation, and Foundation Models frameworks. Report those
  to Apple.
- Problems reproducible only in the upstream
  [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) command-line tool,
  which this project's engine was derived from but no longer runs.
