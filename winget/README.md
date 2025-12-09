# Winget Package Manifest

This directory contains the Windows Package Manager (winget) manifest files for Clarissa.

## Initial Submission

To submit Clarissa to the winget-pkgs repository for the first time:

1. Fork the [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) repository
2. Copy the contents of `manifests/` to your fork under the same path structure
3. Validate the manifest locally:
   ```powershell
   winget validate manifests/c/cameronrye/clarissa/1.3.0/
   ```
4. Create a Pull Request to microsoft/winget-pkgs

## Automated Updates

After the initial submission is accepted, the release workflow will automatically update the manifest for new releases using `wingetcreate`.

## Manual Update

To manually update for a new version:

```powershell
wingetcreate update cameronrye.clarissa --urls "https://github.com/cameronrye/clarissa/releases/download/vX.Y.Z/clarissa-windows-x64.exe" --version X.Y.Z --submit
```

