# Historical snapshots recovered from Web Archive

These directories preserve the repository states corresponding to the dated Web Archive captures. They are recovery snapshots, not additional entries in the IDE's toolchain catalogue.

- ps5-fsr4-2026-09-28: upstream root 3789980ceba27568f2910a561483aa1cee383342, Vulkan submodule 6a0228bedebef949fd2dd90643eae4a5b711c23f.
- ps5-helixsr-2026-10-09: upstream root 028fcd7f737a95183cf688ee4bca8a9e48fe0c40, Vulkan submodule 6875f21438b7e51a1377a30f2d7f77b3e0154cd6.

Root source is restored from mirrors that retain the historical commits. Each Vulkan submodule is recovered from mpereiraesaa/ps5-vulkan at its exact SHA. The synchronizer verifies the commit and Git tree SHA before copying and records provenance in .ps5hs-source.json.

The current toolchain paths toolchains/ps5-fsr4 and toolchains/ps5-helixsr remain on later/current root revisions: FSR4 uses pin 4bb0c8b1423698a7369efc22b829bf16a99e7128; HelixSR uses 6875f21438b7e51a1377a30f2d7f77b3e0154cd6. Do not substitute one version's pin into another without updating its manifest.

The external/ps5-vulkan folders are ordinary tracked files, not nested Git submodules. No proprietary DLLs, firmware, keys, games, ROMs, or BIOS are included. Build dependencies and the legitimate user-supplied DLL that HelixSR requires remain separate.
