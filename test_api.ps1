# ============================================================
# Demo 1: Test script for Notes API with Cognito Auth (PowerShell)
# 
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - Stack deployed via: sam build; sam deploy
#
# Usage:
#   $env:STACK_NAME = "demo-1-notes-api"
#   .\test_api.ps1
# ============================================================

$ErrorActionPreference = "Stop"

$STACK_NAME = if ($env:STACK_NAME) { $env:STACK_NAME } else { "demo-1-notes-api" }
$REGION = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-southeast-3" }
$TEST_EMAIL = "testuser@example.com"
$TEST_PASSWORD = "TestPass1"

Write-Host "=== Fetching stack outputs ===" -ForegroundColor Cyan
$API_URL = aws cloudformation describe-stacks --stack-name $STACK_NAME `
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text --region $REGION
$USER_POOL_ID = aws cloudformation describe-stacks --stack-name $STACK_NAME `
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text --region $REGION
$CLIENT_ID = aws cloudformation describe-stacks --stack-name $STACK_NAME `
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text --region $REGION

Write-Host "API URL:    $API_URL"
Write-Host "Pool ID:    $USER_POOL_ID"
Write-Host "Client ID:  $CLIENT_ID"

Write-Host ""
Write-Host "=== Step 1: Sign up user ===" -ForegroundColor Cyan
try {
    aws cognito-idp sign-up --client-id $CLIENT_ID --username $TEST_EMAIL --password $TEST_PASSWORD --region $REGION 2>$null
} catch { Write-Host "(User may already exist)" }

Write-Host ""
Write-Host "=== Step 2: Admin confirm user ===" -ForegroundColor Cyan
try {
    aws cognito-idp admin-confirm-sign-up --user-pool-id $USER_POOL_ID --username $TEST_EMAIL --region $REGION 2>$null
} catch { Write-Host "(User may already be confirmed)" }

Write-Host ""
Write-Host "=== Step 3: Sign in and get tokens ===" -ForegroundColor Cyan
$AUTH_RESULT = aws cognito-idp initiate-auth `
  --client-id $CLIENT_ID `
  --auth-flow USER_PASSWORD_AUTH `
  --auth-parameters "USERNAME=$TEST_EMAIL,PASSWORD=$TEST_PASSWORD" `
  --region $REGION | ConvertFrom-Json

$ID_TOKEN = $AUTH_RESULT.AuthenticationResult.IdToken
Write-Host "Got ID token (first 50 chars): $($ID_TOKEN.Substring(0,50))..."

Write-Host ""
Write-Host "=== Step 4: Create a note (POST /notes) ===" -ForegroundColor Cyan
$CREATE_BODY = '{"title": "My First Note", "content": "Hello from the serverless notes API!"}'
$CREATE_RESULT = Invoke-RestMethod -Uri "$API_URL/notes" -Method POST `
  -Headers @{ "Authorization" = $ID_TOKEN; "Content-Type" = "application/json" } `
  -Body $CREATE_BODY
$CREATE_RESULT | ConvertTo-Json -Depth 5
$NOTE_ID = $CREATE_RESULT.noteId

Write-Host ""
Write-Host "=== Step 5: Get all notes (GET /notes) ===" -ForegroundColor Cyan
$GET_ALL = Invoke-RestMethod -Uri "$API_URL/notes" -Method GET `
  -Headers @{ "Authorization" = $ID_TOKEN }
$GET_ALL | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "=== Step 6: Get single note (GET /notes/$NOTE_ID) ===" -ForegroundColor Cyan
$GET_ONE = Invoke-RestMethod -Uri "$API_URL/notes/$NOTE_ID" -Method GET `
  -Headers @{ "Authorization" = $ID_TOKEN }
$GET_ONE | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "=== Step 7: Update note (PUT /notes/$NOTE_ID) ===" -ForegroundColor Cyan
$UPDATE_BODY = '{"title": "Updated Note", "content": "Content has been updated!"}'
$UPDATE_RESULT = Invoke-RestMethod -Uri "$API_URL/notes/$NOTE_ID" -Method PUT `
  -Headers @{ "Authorization" = $ID_TOKEN; "Content-Type" = "application/json" } `
  -Body $UPDATE_BODY
$UPDATE_RESULT | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "=== Step 8: Delete note (DELETE /notes/$NOTE_ID) ===" -ForegroundColor Cyan
$DELETE_RESULT = Invoke-RestMethod -Uri "$API_URL/notes/$NOTE_ID" -Method DELETE `
  -Headers @{ "Authorization" = $ID_TOKEN }
$DELETE_RESULT | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "=== Step 9: Verify deletion (GET /notes) ===" -ForegroundColor Cyan
$VERIFY = Invoke-RestMethod -Uri "$API_URL/notes" -Method GET `
  -Headers @{ "Authorization" = $ID_TOKEN }
$VERIFY | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "=== Step 10: Test unauthorized access (no token) ===" -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$API_URL/notes" -Method GET
} catch {
    Write-Host "Got expected error: $($_.Exception.Response.StatusCode) - Unauthorized"
}

Write-Host ""
Write-Host "=== Demo complete! ===" -ForegroundColor Green
