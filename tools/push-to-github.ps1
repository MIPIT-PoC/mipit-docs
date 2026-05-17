# Push all MiPIT repos to GitHub org MIPIT-PoC
# Requisito: ejecutar antes "gh auth login" en una terminal

$ErrorActionPreference = "Stop"

# Comprobar autenticación
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Debes autenticarte primero. Ejecuta en una terminal:" -ForegroundColor Yellow
    Write-Host "  gh auth login" -ForegroundColor Cyan
    Write-Host "Luego vuelve a ejecutar este script." -ForegroundColor Yellow
    exit 1
}
$repos = @(
    "mipit-infra",
    "mipit-core",
    "mipit-adapter-pix",
    "mipit-adapter-spei",
    "mipit-ui",
    "mipit-observability",
    "mipit-docs",
    "mipit-testkit"
)

# Run from Tesis folder: .\scripts\push-to-github.ps1
$root = if (Test-Path "mipit-infra") { Get-Location } else { Split-Path -Parent $PSScriptRoot }
Set-Location $root

foreach ($r in $repos) {
    $path = Join-Path $root $r
    if (-not (Test-Path $path)) { Write-Warning "Skip $r (folder not found)"; continue }
    Push-Location $path
    try {
        $remotes = git remote 2>$null | Out-String
        if (-not $remotes -or $remotes -notmatch "origin") {
            Write-Host "Creating MIPIT-PoC/$r and pushing..."
            gh repo create "MIPIT-PoC/$r" --public --source=. --remote=origin --push
        } else {
            Write-Host "Pushing $r to origin..."
            $branch = git branch --show-current 2>$null; if (-not $branch) { $branch = "master" }
            git push -u origin $branch
        }
        Write-Host "OK: $r" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: $r - $_" -ForegroundColor Red
    }
    Pop-Location
}
Write-Host "Done."
