# Source archive — Visual-PS5 v1.0.1

The exact compressed source distribution is stored as twenty ordered Base64 text segments (the original fourteen chunks were split into smaller pieces for transport) in this folder because the connected GitHub interface can write text files but cannot attach binary release assets. Reassemble them with the supplied scripts before extracting the project.

- Format: XZ-compressed TAR
- Archive filename: PS5-Homebrew-Studio-v1.0.1.tar.xz
- SHA-256: f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13

Do not edit the segment contents. They are transport data, not source code. Run the restore script from the repository root or clone checkout. After decoding, the script verifies the full archive hash; extraction should produce the PS5-Homebrew-Studio/ directory.

This is a transport workaround, not a conventional GitHub Release asset. When publishing a release, also attach the ZIP and its SHA-256 via the GitHub Releases UI; see docs/PUBLICACION-DE-RELEASE.es-ES.md or docs/RELEASING.en-GB.md.
