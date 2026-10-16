# Licensing and security

## Licensing

The IDE itself is distributed under the licence supplied in its \`LICENSE\` file. GitHub templates, libraries, SDKs and drivers keep their own licences, copyright notices, redistribution conditions and source-disclosure obligations. The IDE's licence does **not** replace or automatically inherit upstream licences.

Before distributing a generated project:
1. Record the exact repository and commit for each dependency.
2. Read \`LICENSE\`, \`COPYING\`, \`NOTICE\`, \`THIRD_PARTY_NOTICES\` and relevant documentation in each repository.
3. Check transitive dependencies, assets, shaders, fonts and packaged resources.
4. Preserve notices and source-code offers where required.
5. Do not confuse an optional GPL UI module with the base template's licence, and do not assume the whole stack has one licence.
6. Review each project's distribution terms and obtain legal advice where needed.

Catalogue licence labels are informative notes recorded during preparation, not a definitive legal conclusion. “Review upstream” means the user must inspect the actual licence at the downloaded commit.

## Sony files and trademarks

Visual-PS5 is not an official Sony product and is not endorsed by Sony. It contains no firmware, keys, proprietary Sony files, games, ROMs, BIOS or payload intended to bypass protections. Users are responsible for having lawful rights to the environment, game resources and devices they use.

## Local security

- The service listens on \`127.0.0.1:47813\`; do not bind it to a public network interface.
- Fetch toolchains only from the declared upstream repositories and inspect commits before running scripts.
- A build may execute Make, Python, shell and other third-party tooling. Inspect scripts and permissions; do not run privileged builds without understanding them.
- The workspace contains local code and assets. Do not open untrusted projects without reviewing them.
- Do not store credentials, tokens, keys or secrets in the model, logs, issue reports or repository.
- Keep logs free of secrets and do not attach private dumps or protected game content.
- Browser \`localStorage\` is not an encrypted backup.
- Static checks and a ZIP hash are not a security audit or a trusted cryptographic signature.

## Fault reports

Include version, operating system, PowerShell version, backend, dependency commits, reproducible steps and sanitised logs. Do not claim firmware/hardware compatibility that has not been tested.

## Known validation status

Preparation included JavaScript syntax checks and generator tests; generated C++ syntax was checked against test interfaces. The official PowerShell parser, complete PS5 toolchain and physical hardware were unavailable. A real build with the final SDK is therefore not claimed.

## Subsequent hardware test reported by the maintainer

The maintainer reported that a generated .ffpfsc image worked on real hardware. This specific test is not a security audit and does not guarantee compatibility across all titles or firmware versions.
