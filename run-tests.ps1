

# --- Configuration ---
# IMPORTANT: Ensure you are using straight quotes " " and not curly quotes “ ”
$DEPLOYER_ADDRESS = "ST336VQZA4VAGC9RQVX5F95FCCSVBV99Z3JA1MJJ9"
$PRIVATE_KEY = "fbcfcd5f33b3326b3820c32f4006182d7fb3b931cd31a01f34b00379b5e8ed5b01"

# --- Script Start ---
Write-Host "🧪 Running Arcadia Protocol Integration Tests..." -ForegroundColor Cyan

Write-Warning "Using private key directly in scripts is insecure. Use for testing only."

# --- Test 1 ---
Write-Host "`nTest 1: Full home purchase flow..." -ForegroundColor Yellow
stx call_contract_func `
  -t `
  --private_key $PRIVATE_KEY `
  $DEPLOYER_ADDRESS `
  test-scenarios `
  test-home-purchase-flow `
  --fee 10000

# --- Test 2 ---
Write-Host "`nTest 2: Yield processing..." -ForegroundColor Yellow
stx call_contract_func `
  -t `
  --private_key $PRIVATE_KEY `
  $DEPLOYER_ADDRESS `
  test-scenarios `
  test-yield-processing `
  -e "u1" `
  --fee 5000

# --- Test 3 ---
Write-Host "`nTest 3: Stability pool protection..." -ForegroundColor Yellow
stx call_contract_func `
  -t `
  --private_key $PRIVATE_KEY `
  $DEPLOYER_ADDRESS `
  test-scenarios `
  test-stability-pool-protection `
  --fee 5000

# --- Test 4 ---
Write-Host "`nTest 4: Full integration test..." -ForegroundColor Yellow
stx call_contract_func `
  -t `
  --private_key $PRIVATE_KEY `
  $DEPLOYER_ADDRESS `
  test-scenarios `
  run-all-tests `
  --fee 15000


Write-Host "`n✅ Integration tests complete!" -ForegroundColor Green
Write-Host "Check transaction results in the explorer."