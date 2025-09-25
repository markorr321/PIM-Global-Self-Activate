# PIM-Global-MST - Developer Documentation

A standalone executable for Entra ID Privileged Identity Management (PIM) role activation with enforced MFA and Microsoft Teams integration.

## Overview

This project creates a single-file executable (`PIM-Global-SA.exe`) that:
- Embeds the PowerShell script and MSAL.NET DLLs as resources
- Extracts everything to a temporary directory at runtime
- Launches PowerShell 7+ with the script
- Brings the console window to the foreground
- Cleans up temporary files when done

## Prerequisites

- **.NET 6 SDK** - Download from [Microsoft](https://dotnet.microsoft.com/download/dotnet/6.0)
- **PowerShell 7+** - The target machine must have PowerShell 7+ installed
- **PIM-Global-SelfActivate.ps1** - Your PowerShell script (must be in the project root)
- **MSAL DLLs** - Must be in `MSAL\netstandard2.0\` directory:
  - `Microsoft.Identity.Client.dll`
  - `Microsoft.IdentityModel.Abstractions.dll`
- **PIM.ico** - Icon file for the executable (optional)

## Project Structure

```
PIM-Global-MST/
├── Program.cs                      # Main C# launcher code
├── PIMGlobalMSTLauncher.csproj     # Project file
├── PIM-Global-SelfActivate.ps1      # PowerShell script with Teams integration
├── PIM.ico                         # Application icon
├── MSAL/
│   └── netstandard2.0/
│       ├── Microsoft.Identity.Client.dll
│       └── Microsoft.IdentityModel.Abstractions.dll
├── out/                            # Build output directory
├── README.md                       # End-user documentation
├── DEVELOPER-README.md             # This file (developer documentation)
└── CONFIGURATION.md                # Detailed setup guide
```

## Building the Executable

### Build Commands
```cmd
dotnet clean
dotnet restore
dotnet publish PIMGlobalMSTLauncher.csproj -c Release
```

### Advanced Build Options
```cmd
# Build with specific runtime
dotnet publish PIMGlobalMSTLauncher.csproj -c Release -r win-x64 --self-contained true

# Build single file (larger but truly portable)
dotnet publish PIMGlobalMSTLauncher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Output

The build creates the executable at:
```
.\out\PIM-Global-SA.exe
```

This EXE file:
- Contains all necessary resources embedded
- Is self-contained (includes .NET runtime)
- Can be distributed as a single file
- Requires PowerShell 7+ on the target machine

## How It Works

1. **Extraction**: The EXE extracts `PIM-Global-SelfActivate.ps1` and MSAL DLLs to a temporary directory
2. **PowerShell Detection**: Finds `pwsh.exe` in common installation paths or PATH
3. **Launch**: Starts PowerShell 7+ with the script using proper arguments
4. **Window Management**: Ensures PowerShell opens in its own window (not CMD)
5. **Cleanup**: Removes temporary files when PowerShell exits

## Development Notes

### Embedded Resources
The project embeds these files as resources in the executable:
- `PIM-Global-SelfActivate.ps1` - Main PowerShell script
- `Microsoft.Identity.Client.dll` - MSAL authentication library
- `Microsoft.IdentityModel.Abstractions.dll` - Identity model abstractions

### Resource Naming Convention
Embedded resources follow the pattern: `{Namespace}.{Path.With.Dots}`
- `PIMGlobalMSTLauncher.PIM-Global-SelfActivate.ps1`
- `PIMGlobalMSTLauncher.MSAL.netstandard2._0.Microsoft.Identity.Client.dll`

### PowerShell Launch Configuration
```csharp
ProcessStartInfo = new ProcessStartInfo
{
    FileName = pwshPath,
    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
    UseShellExecute = true,
    WindowStyle = ProcessWindowStyle.Normal
}
```

## Troubleshooting

### PowerShell 7+ Not Found
The launcher checks these locations for `pwsh.exe`:
- `C:\Program Files\PowerShell\7\pwsh.exe`
- `C:\Program Files (x86)\PowerShell\7\pwsh.exe`
- PATH environment variable

### Missing Resources
Ensure these files exist before building:
- `PIM-Global-SelfActivate.ps1` in project root
- `MSAL\netstandard2.0\Microsoft.Identity.Client.dll`
- `MSAL\netstandard2.0\Microsoft.IdentityModel.Abstractions.dll`

### Build Errors
- Verify .NET 6 SDK is installed: `dotnet --version`
- Check that all required files are present
- Ensure no files are locked by other processes
- Try cleaning: `dotnet clean` before building

### Runtime Issues
- Check Windows event logs for .NET application errors
- Verify PowerShell 7+ is installed on target machine
- Ensure user has permissions to create files in temp directory

## Distribution

### Building the Executable
Use the provided build script for easy compilation:
```powershell
.\build.ps1
```

Or manually:
```bash
dotnet clean PIMGlobalMSTLauncher.csproj
dotnet restore PIMGlobalMSTLauncher.csproj
dotnet publish PIMGlobalMSTLauncher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

### GitHub Releases
**⚠️ Important**: The EXE file is too large for Git commits (typically 60-100MB). Instead:

1. **Source code goes in Git** - The `.gitignore` already excludes `*.exe` and `out/` directory
2. **EXE distributed via GitHub Releases** - Upload the compiled executable as a release asset
3. **Users download from Releases page** - Point users to the latest release for the EXE download

### Release Process
1. Build the executable: `.\build.ps1`
2. Test the EXE thoroughly
3. Create a Git tag: `git tag v3.0.1`
4. Push to GitHub: `git push origin v3.0.1`
5. Create GitHub Release and attach `.\out\PIM-Global-SA.exe`

The resulting `PIM-Global-SA.exe` is a completely standalone executable that:
- Requires no installation
- Contains all necessary components
- Works on any Windows 10/11 x64 machine with PowerShell 7+
- Cleans up after itself
- Provides user-friendly error messages

## Security Notes

- The EXE extracts files to the system temp directory
- Temporary files are automatically cleaned up
- No permanent files are left on the system
- The PowerShell script runs with the same permissions as the user
- All authentication is handled by Microsoft's MSAL library

## Version Information

Current version: 4.0.0
- Semantic versioning implemented in both C# project and PowerShell script
- Version information embedded in executable metadata
- Release notes maintained in GitHub releases

## Documentation Structure

- **[README.md](README.md)** - End-user guide for using the executable
- **[DEVELOPER-README.md](DEVELOPER-README.md)** - This file (developer documentation)
- **[CONFIGURATION.md](CONFIGURATION.md)** - Detailed setup guide for Teams integration
- **[GitHub Releases](https://github.com/markorr321/PIM-Global-Self-Activate/releases)** - Download links and release notes
