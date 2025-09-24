#!/usr/bin/env pwsh
# Build script for PIM-Global-SelfActivate
# Builds the self-contained executable

Write-Host "🔨 Building PIM-Global-SelfActivate..." -ForegroundColor Cyan

# Clean previous builds
Write-Host "🧹 Cleaning previous builds..." -ForegroundColor Yellow
dotnet clean PIMGlobalMSTLauncher.csproj

# Restore dependencies
Write-Host "📦 Restoring dependencies..." -ForegroundColor Yellow
dotnet restore PIMGlobalMSTLauncher.csproj

# Build and publish (framework-dependent - much smaller)
Write-Host "🚀 Building executable..." -ForegroundColor Yellow
dotnet publish PIMGlobalMSTLauncher.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build completed successfully!" -ForegroundColor Green
    Write-Host "📁 Output location: .\out\PIM-Global-MST.exe" -ForegroundColor Green
    
    # Check if file exists and show size
    $exePath = ".\out\PIM-Global-MST.exe"
    if (Test-Path $exePath) {
        $fileSize = (Get-Item $exePath).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "📊 File size: $fileSizeMB MB" -ForegroundColor Cyan
    }
} else {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}
