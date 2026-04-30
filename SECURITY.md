# Security Policy

## Supported versions

Only the latest tagged release is actively supported. Older releases will not
receive backports.

## Reporting a vulnerability

If you find a security issue — for example, a path-traversal in how filenames
are handled, a crash that could be triggered by a malicious subtitle file,
or anything that could leak data from a user's machine — please **don't open
a public GitHub issue.**

Instead, email **jeff.alldridge@gmail.com** with:

- A description of the issue
- Steps to reproduce (a minimal `.mkv` or `.sup` is helpful)
- Your suggested severity rating

You should expect a response within a few days. Once the issue is fixed and
released, you'll be credited in the changelog (unless you'd rather stay
anonymous).

## Scope

This is a Mac-only tool that runs locally and does not phone home or perform
network operations beyond `make update` (a Homebrew-style submodule bump
under your control). Practical attack surface is:

- Parsing untrusted `.mkv` / `.sup` / `.sub` / `.idx` files
- Shelling out to `mkvmerge` and `mkvextract` (system-installed)
- File-system writes to the user's chosen output directory

Issues outside this scope are usually better reported upstream — e.g.
OCR-engine bugs to [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR)
or [MKVToolNix](https://gitlab.com/mbunkus/mkvtoolnix).
