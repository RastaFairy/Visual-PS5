# Publishing a Visual-PS5 GitHub release

This procedure explains how to publish the v1.0.1 binary ZIP as a release asset. The repository currently contains the bilingual documentation; the corrected ZIP is supplied separately and must be attached manually as a GitHub Release asset before visitors can download it from the repository page.

## Before publishing

1. Download the supplied PS5-Homebrew-Studio-v1.0.1.zip and PS5-Homebrew-Studio-v1.0.1.sha256 files.
2. Verify that the ZIP hash exactly matches the SHA-256 file.
3. Do not describe this release as “tested on PS5”: static generator tests were run, but the complete SDK and a physical console were not available for validation.
4. Keep the repository private unless a deliberate decision has been made to make it public.

## Create the release

1. Open RastaFairy/Visual-PS5 on GitHub.
2. Open **Releases** and select **Draft a new release**.
3. Create tag **v1.0.1** against the default branch and use the title **Visual-PS5 / PS5 Homebrew Studio v1.0.1**.
4. Attach both the ZIP and SHA-256 files in the release assets area. Do not paste the ZIP into a Markdown file or rename it without recalculating the hash.
5. State in the notes that v1.0.1 fixes PowerShell interpolation in SaveProject, while validation with the real PowerShell parser/SDK and physical hardware remains outstanding.
6. Check repository visibility and select **Publish release**.

## Post-publication check

Download the published release to a clean directory, recalculate SHA-256 and test the ZIP with your system's archive utility. Then test it on Windows PowerShell 7.6.7, run start.bat and retain the parser output. Only after a successful upstream build and hardware test should claims about those environments be added.