#!/bin/bash
# ============================================================
# Demo 1: Test script for Notes API with Cognito Auth
# 
# This script walks through the full auth flow:
#   1. Sign up a user in Cognito
#   2. Confirm the user (admin)
#   3. Sign in and get JWT tokens
#   4. Use the ID token to call the API (CRUD operations)
#
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - jq installed (for JSON parsing)
#   - Stack deployed via: sam build && sam deploy
#
# Usage:
#   export STACK_NAME=demo-1-notes-api
#   bash test_api.sh
# ============================================================

set -e

STACK_NAME="${STACK_NAME:-demo-1-notes-api}"
REGION="${AWS_REGION:-ap-southeast-3}"
TEST_EMAIL="testuser@example.com"
TEST_PASSWORD="TestPass1"

echo "=== Fetching stack outputs ==="
API_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text --region $REGION)
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text --region $REGION)
CLIENT_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text --region $REGION)

echo "API URL:    $API_URL"
echo "Pool ID:    $USER_POOL_ID"
echo "Client ID:  $CLIENT_ID"

echo ""
echo "=== Step 1: Sign up user ==="
aws cognito-idp sign-up \
  --client-id $CLIENT_ID \
  --username $TEST_EMAIL \
  --password $TEST_PASSWORD \
  --region $REGION 2>/dev/null || echo "(User may already exist)"

echo ""
echo "=== Step 2: Admin confirm user ==="
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id $USER_POOL_ID \
  --username $TEST_EMAIL \
  --region $REGION 2>/dev/null || echo "(User may already be confirmed)"

echo ""
echo "=== Step 3: Sign in and get tokens ==="
AUTH_RESULT=$(aws cognito-idp initiate-auth \
  --client-id $CLIENT_ID \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=$TEST_EMAIL,PASSWORD=$TEST_PASSWORD \
  --region $REGION)

ID_TOKEN=$(echo $AUTH_RESULT | jq -r '.AuthenticationResult.IdToken')
echo "Got ID token (first 50 chars): ${ID_TOKEN:0:50}..."

echo ""
echo "=== Step 4: Create a note (POST /notes) ==="
CREATE_RESULT=$(curl -s -X POST "$API_URL/notes" \
  -H "Authorization: $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "My First Note", "content": "Hello from the serverless notes API!"}')
echo $CREATE_RESULT | jq .

NOTE_ID=$(echo $CREATE_RESULT | jq -r '.noteId')

echo ""
echo "=== Step 5: Get all notes (GET /notes) ==="
curl -s "$API_URL/notes" -H "Authorization: $ID_TOKEN" | jq .

echo ""
echo "=== Step 6: Get single note (GET /notes/{noteId}) ==="
curl -s "$API_URL/notes/$NOTE_ID" -H "Authorization: $ID_TOKEN" | jq .

echo ""
echo "=== Step 7: Update note (PUT /notes/{noteId}) ==="
curl -s -X PUT "$API_URL/notes/$NOTE_ID" \
  -H "Authorization: $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Updated Note", "content": "Content has been updated!"}' | jq .

echo ""
echo "=== Step 8: Delete note (DELETE /notes/{noteId}) ==="
curl -s -X DELETE "$API_URL/notes/$NOTE_ID" \
  -H "Authorization: $ID_TOKEN" | jq .

echo ""
echo "=== Step 9: Verify deletion (GET /notes) ==="
curl -s "$API_URL/notes" -H "Authorization: $ID_TOKEN" | jq .

echo ""
echo "=== Step 10: Test unauthorized access (no token) ==="
curl -s "$API_URL/notes" | jq .

echo ""
echo "=== Demo complete! ==="
