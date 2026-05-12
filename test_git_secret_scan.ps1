
# =============================================================================
# SimpleDLP - Double Guard Git Secret Scanning - End-to-End Test Script
# =============================================================================
# USAGE: .\test_git_secret_scan.ps1
#
# PRE-REQUISITES:
#   1. Agent (dlp-proxy-new.exe) is RUNNING with the proxy active
#   2. CMS is RUNNING and the network policy is synced to the agent
#   3. Git Push guard is ENABLED in the CMS Network Policy
#   4. "Scan for Sensitive Patterns" is ENABLED in the Git Push tab
#   5. The repo "phatdo1819/simpledlp" (or the relevant repo) is in the ALLOWED list
#   6. At least one sensitive pattern is configured (e.g. AKIA[0-9A-Z]{16} for AWS)
# =============================================================================

$ErrorActionPreference = "Continue"
$repo = "c:\Users\admin\simpledlp"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  SimpleDLP Double Guard - Git Secret Scan Test" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# --- Helper ---
function Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Info($msg) { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

# =============================================================================
# TEST 1: Clean push (no secrets) should SUCCEED
# =============================================================================
Write-Host "--- TEST 1: Clean push (no secrets) ---" -ForegroundColor White
$cleanFile = "$repo\__dlp_test_clean.txt"
Set-Content -Path $cleanFile -Value "This is a clean file with no secrets. Just regular code."

Push-Location $repo
git add $cleanFile | Out-Null
git commit -m "DLP-TEST: Clean file commit [no secrets]" | Out-Null
Pop-Location

Info "Attempting git push (expect: SUCCESS)..."
Push-Location $repo
$pushOutput = git push origin HEAD 2>&1
$pushExitCode = $LASTEXITCODE
Pop-Location

# Clean up the test file and commit immediately to keep repo clean
Push-Location $repo
git rm -f $cleanFile | Out-Null
git commit -m "DLP-TEST: Remove clean test file" | Out-Null
Pop-Location

if ($pushExitCode -eq 0) {
    Pass "Test 1 PASSED - Clean push succeeded as expected."
} else {
    Fail "Test 1 FAILED - Clean push was unexpectedly blocked!"
    Info "Output: $pushOutput"
}

Write-Host ""

# =============================================================================
# TEST 2: Push with fake AWS key should be BLOCKED
# =============================================================================
Write-Host "--- TEST 2: Push with fake AWS Access Key (expect BLOCK) ---" -ForegroundColor White
$secretFile = "$repo\__dlp_test_aws_secret.env"
Set-Content -Path $secretFile -Value @"
# Fake credentials for DLP testing - NOT REAL
AWS_ACCESS_KEY_ID=AKIAEXAMPLE123456789
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
REGION=us-east-1
"@

Push-Location $repo
git add $secretFile | Out-Null
git commit -m "DLP-TEST: Commit with fake AWS secret [should be blocked]" | Out-Null
Pop-Location

Info "Attempting git push with AWS key (expect: BLOCKED by DLP)..."
Push-Location $repo
$pushOutput = git push origin HEAD 2>&1
$pushExitCode = $LASTEXITCODE
Pop-Location

# Always clean up the commit regardless of result
Push-Location $repo
git reset HEAD~1 --soft | Out-Null  # Unstage the blocked commit if it was not pushed
git checkout -- . | Out-Null
git clean -fd __dlp_test* | Out-Null
Pop-Location

if ($pushExitCode -ne 0) {
    Pass "Test 2 PASSED - AWS key push was BLOCKED by Double Guard."
    Info "Push output: $pushOutput"
} else {
    Fail "Test 2 FAILED - Push with AWS key was NOT blocked! Check your sensitive patterns."
    Info "Verify pattern 'AKIA[0-9A-Z]{16}' is added in CMS Content Policy > Sensitive Patterns"
}

Write-Host ""

# =============================================================================
# TEST 3: Push with fake OpenAI key should be BLOCKED
# =============================================================================
Write-Host "--- TEST 3: Push with fake OpenAI key (expect BLOCK) ---" -ForegroundColor White
$openaiFile = "$repo\__dlp_test_openai.py"
Set-Content -Path $openaiFile -Value @"
import openai
# Fake key for DLP testing - NOT REAL
openai.api_key = "sk-abc123def456ghi789jkl012mno345pqr678stu901vwx234"
"@

Push-Location $repo
git add $openaiFile | Out-Null
git commit -m "DLP-TEST: Commit with fake OpenAI key [should be blocked]" | Out-Null
Pop-Location

Info "Attempting git push with OpenAI key (expect: BLOCKED by DLP)..."
Push-Location $repo
$pushOutput = git push origin HEAD 2>&1
$pushExitCode = $LASTEXITCODE
Pop-Location

# Clean up
Push-Location $repo
git reset HEAD~1 --soft | Out-Null
git checkout -- . | Out-Null
git clean -fd __dlp_test* | Out-Null
Pop-Location

if ($pushExitCode -ne 0) {
    Pass "Test 3 PASSED - OpenAI key push was BLOCKED by Double Guard."
} else {
    Fail "Test 3 FAILED - Push with OpenAI key was NOT blocked!"
    Info "Verify pattern 'sk-[a-zA-Z0-9]{48}' is added in CMS Content Policy > Sensitive Patterns"
}

Write-Host ""

# =============================================================================
# TEST 4: Unauthorized repo push should be BLOCKED (before even scanning)
# =============================================================================
Write-Host "--- TEST 4: Unauthorized remote push (expect BLOCK at header level) ---" -ForegroundColor White
Info "Attempting push to a fake unauthorized URL..."
Push-Location $repo
$pushOutput = git push https://github.com/unauthorized-org/secret-repo.git HEAD 2>&1
$pushExitCode = $LASTEXITCODE
Pop-Location

if ($pushExitCode -ne 0) {
    Pass "Test 4 PASSED - Unauthorized repo push was blocked."
} else {
    Fail "Test 4 FAILED - Unauthorized repo was not blocked!"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Test Complete. Check CMS Events tab for logged blocks." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log marker to search in CMS Events: 'DLP-TEST'" -ForegroundColor Yellow
