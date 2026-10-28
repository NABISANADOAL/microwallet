$ErrorActionPreference = 'Stop'
$WorkerName = 'microwallet-repaired-20261025'
Write-Host 'MicroWallet - Cloudflare Workers deployment' -ForegroundColor Cyan
Write-Host 'This updates the existing Worker name, preserving its workers.dev URL.' -ForegroundColor Yellow
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is not installed. Install Node.js LTS first.' }
if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) { throw 'npx.cmd was not found. Reinstall/repair Node.js, then reopen PowerShell.' }
Write-Host 'Checking Cloudflare login...' -ForegroundColor Cyan
npx.cmd wrangler whoami
if ($LASTEXITCODE -ne 0) { throw 'Cloudflare login check failed. Run: npx.cmd wrangler login' }
Write-Host 'Deploying MicroWallet frontend...' -ForegroundColor Cyan
npx.cmd wrangler deploy --config .\wrangler.jsonc
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed. Copy the full error output.' }
Write-Host ''
Write-Host 'Finished. Open:' -ForegroundColor Green
Write-Host 'https://microwallet-repaired-20261025.nabisanadgoal0311.workers.dev/' -ForegroundColor Green
