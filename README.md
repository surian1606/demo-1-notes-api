# Demo 1: Serverless Notes API with Cognito Auth

A full-stack serverless CRUD application for personal notes, built entirely with AWS managed services and deployed as infrastructure as code using AWS SAM. This demo covers concepts from Modules 1–4 and 7 of the Developing Serverless Solutions on AWS course.

## Prerequisites

### Software Requirements

| Tool | Version | Installation |
|---|---|---|
| AWS CLI | v2.x | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| AWS SAM CLI | v1.x | `pip install aws-sam-cli` or https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html |
| Python | 3.12 | https://www.python.org/downloads/ — required for `sam build` to package the Lambda functions |
| Git | any | To clone the project (optional if copying files directly) |

### AWS Account Requirements

| Requirement | Details |
|---|---|
| AWS Account | An active AWS account with billing enabled |
| IAM Permissions | The deploying user/role needs permissions to create: CloudFormation stacks, Lambda functions, API Gateway REST APIs, DynamoDB tables, Cognito User Pools, IAM roles/policies, and S3 buckets (for SAM deployment artifacts). Using an IAM user or role with `AdministratorAccess` is simplest for a demo; for production, scope down to the specific services listed. |
| AWS Region | Any Region that supports all services used (Lambda, API Gateway, DynamoDB, Cognito). The project defaults to `ap-southeast-3` but can be changed. |
| SES Sandbox (Cognito emails) | Cognito uses Amazon SES to send verification codes. In a new account, SES is in sandbox mode — verification emails will still be delivered, but may land in spam. No SES configuration is needed; Cognito uses its default email sender. For production, configure a verified SES identity in the Cognito User Pool. |

### AWS CLI Configuration

Configure credentials for the target account:

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, Default Region, Output format
```

Or use named profiles:

```bash
aws configure --profile demo
export AWS_PROFILE=demo
```

Or use SSO:

```bash
aws configure sso
aws sso login --profile your-sso-profile
export AWS_PROFILE=your-sso-profile
```

Verify access:

```bash
aws sts get-caller-identity
```

## Architecture Overview

```
┌──────────────────┐       HTTPS        ┌──────────────────────────────────┐
│                  │  ───────────────►   │  Amazon API Gateway (REST API)   │
│   Browser Client │                    │  - Cognito Authorizer on all     │
│   (index.html)   │  ◄───────────────  │    routes (except OPTIONS)       │
│                  │    JSON response    │  - CORS enabled                  │
└──────┬───────────┘                    └──────────┬───────────────────────┘
       │                                           │ Proxy integration
       │  SRP Auth                                 ▼
       │                                ┌──────────────────────────┐
       │                                │   AWS Lambda (Python 3.12)│
       │                                │   5 functions:            │
       │                                │   - create\_note (POST)    │
       │                                │   - get\_notes  (GET)      │
       │                                │   - get\_note   (GET/:id)  │
       │                                │   - update\_note (PUT/:id) │
       │                                │   - delete\_note (DEL/:id) │
       │                                └──────────┬───────────────┘
       │                                           │ IAM execution role
       ▼                                           ▼
┌──────────────────┐                    ┌──────────────────────────┐
│  Amazon Cognito   │                    │  Amazon DynamoDB          │
│  User Pool        │                    │  (PAY\_PER\_REQUEST)        │
│  - Self-service   │                    │  PK: userId (String)      │
│    sign-up        │                    │  SK: noteId  (String)     │
│  - Email verify   │                    └──────────────────────────┘
│  - JWT tokens     │
└──────────────────┘
```

All resources are defined in a single `template.yaml` and deployed via `sam build \&\& sam deploy`. The SAM Transform converts the template into CloudFormation, which provisions and manages the entire stack.

## Service-by-Service Configuration

### 1\. Amazon Cognito User Pool (Authentication — Module 3)

Cognito acts as the identity provider (IdP) for the application. It handles user registration, email verification, and JWT token issuance.

|Setting|Value|Why|
|-|-|-|
|UsernameAttributes|`email`|Users sign in with their email address instead of a separate username|
|AutoVerifiedAttributes|`email`|Cognito automatically sends a verification code to the user's email on sign-up|
|AdminCreateUserConfig|`AllowAdminCreateUserOnly: false`|Enables self-service sign-up so users can register themselves from the web client|
|PasswordPolicy|Min 8 chars, upper + lower + numbers, no symbols required|Balances security with usability for a demo|
|Schema|`email` required and mutable|Email is the only required attribute|

The User Pool Client is configured with:

* `ALLOW\_USER\_SRP\_AUTH` — Secure Remote Password protocol used by the browser SDK (`amazon-cognito-identity-js`). SRP never sends the password over the network; instead it uses a zero-knowledge proof.
* `ALLOW\_USER\_PASSWORD\_AUTH` — Simpler auth flow used by the CLI test script and `aws cognito-idp initiate-auth`.
* `ALLOW\_REFRESH\_TOKEN\_AUTH` — Allows the client to silently refresh expired ID/Access tokens using the Refresh token.
* `GenerateSecret: false` — Required for browser-based clients that cannot securely store a client secret.

On successful authentication, Cognito issues three JWTs:

* ID Token — contains user identity claims (`sub`, `email`). Passed to API Gateway for authorization.
* Access Token — used for OAuth scope-based authorization (not used in this demo).
* Refresh Token — used to obtain new ID/Access tokens without re-authenticating.

### 2\. Amazon API Gateway — REST API (Synchronous Event Source — Module 2)

API Gateway is the front door to the application. It receives HTTPS requests from the browser, validates the JWT token, and proxies the request to the appropriate Lambda function.

|Setting|Value|Why|
|-|-|-|
|Type|`AWS::Serverless::Api` (REST API)|SAM resource that creates an API Gateway REST API with Lambda proxy integration|
|StageName|`${Environment}` (defaults to `dev`)|Supports multi-environment deployment from a single template|
|DefaultAuthorizer|`CognitoAuthorizer`|Every route requires a valid Cognito ID token in the `Authorization` header|
|AddDefaultAuthorizerToCorsPreflight|`false`|OPTIONS preflight requests must pass without a token — browsers send these automatically before the real request|
|CORS AllowOrigin|`\*`|Permits requests from any origin (the client runs from a local `file://` or any domain)|
|CORS AllowHeaders|`Content-Type, Authorization`|The two headers the client sends|
|CORS AllowMethods|`GET, POST, PUT, DELETE, OPTIONS`|All HTTP methods used by the API|

API Gateway invokes Lambda synchronously — the client sends a request and waits for the response. There are no built-in retries; if Lambda returns an error, it goes straight back to the client. The built-in timeout is 30 seconds.

Routes:

|Method|Path|Lambda Handler|Description|
|-|-|-|-|
|POST|`/notes`|`create\_note.handler`|Create a new note|
|GET|`/notes`|`get\_notes.handler`|List all notes for the authenticated user|
|GET|`/notes/{noteId}`|`get\_note.handler`|Get a single note by ID|
|PUT|`/notes/{noteId}`|`update\_note.handler`|Update an existing note|
|DELETE|`/notes/{noteId}`|`delete\_note.handler`|Delete a note|

### 3\. AWS Lambda Functions (Serverless Compute — Module 7)

Five Lambda functions handle the business logic. They follow key best practices from Module 7:

|Setting|Value|Why|
|-|-|-|
|Runtime|Python 3.12|Latest stable Python runtime|
|Timeout|15 seconds|Short timeout for simple CRUD operations — avoids paying for stuck functions|
|MemorySize|256 MB|Provides proportional CPU; sufficient for DynamoDB I/O-bound operations|
|Architecture|x86\_64|Default architecture|
|Environment Variable|`TABLE\_NAME` (resolved via `!Ref NotesTable`)|Externalizes the table name so the same code works across environments|

Best practices applied:

* DynamoDB client initialized outside the handler (`dynamodb = boto3.resource("dynamodb")`) — reused across warm invocations, avoiding re-initialization on every request.
* Structured JSON error logging (`json.dumps({"level": "ERROR", "message": ...})`) — enables CloudWatch Logs Insights queries.
* User isolation via Cognito `sub` claim — each function extracts `userId` from `event\["requestContext"]\["authorizer"]\["claims"]\["sub"]`, ensuring users can only access their own notes.
* Least-privilege IAM — read-only functions (`get\_notes`, `get\_note`) use `DynamoDBReadPolicy`; write functions use `DynamoDBCrudPolicy`. SAM policy templates automatically scope permissions to the specific table.
* Conditional DynamoDB expressions — `update\_note` and `delete\_note` use `ConditionExpression="attribute\_exists(userId)"` to return 404 instead of silently succeeding on non-existent items.
* CORS headers in every response — Lambda returns `Access-Control-Allow-Origin: \*` so the browser accepts the response.

### 4\. Amazon DynamoDB Table (Purpose-Built Data Store — Module 1)

DynamoDB stores the notes with a composite primary key that naturally partitions data by user.

|Setting|Value|Why|
|-|-|-|
|BillingMode|`PAY\_PER\_REQUEST` (on-demand)|No capacity planning needed; scales automatically; cost-effective for variable/demo workloads|
|Partition Key (PK)|`userId` (String)|Groups all notes by user — enables efficient `Query` to list a user's notes|
|Sort Key (SK)|`noteId` (String, UUID)|Uniquely identifies each note within a user's partition|

Each item contains: `userId`, `noteId`, `title`, `content`, `createdAt`, `updatedAt`.

The composite key design means:

* `Query` on `userId` returns all notes for a user (used by `get\_notes`)
* `GetItem` on `userId + noteId` retrieves a specific note (used by `get\_note`)
* No scan operations are needed — all access patterns are served by the primary key

### 5\. AWS SAM \& CloudFormation (Deployment Framework — Module 4)

The entire stack is defined in a single `template.yaml` using the AWS SAM Transform (`AWS::Serverless-2016-10-31`). SAM simplifies the template by:

* Auto-creating IAM execution roles from policy templates (`DynamoDBCrudPolicy`, `DynamoDBReadPolicy`)
* Auto-creating API Gateway integrations from `Events` blocks on functions
* Auto-creating the Lambda permission (resource-based policy) allowing API Gateway to invoke each function
* Supporting `Globals` to avoid repeating runtime, timeout, memory, and environment config across 5 functions

The `Parameters` section accepts an `Environment` value (`dev`, `staging`, `prod`) that is interpolated into all resource names via `!Sub`, enabling multi-environment deployment from the same template.

`samconfig.toml` stores deployment defaults (stack name, region, capabilities) so subsequent deploys require only `sam deploy`.

## Client Application

The web client (`client/index.html`) is a single-file HTML/CSS/JS application with no build step. It uses:

* `amazon-cognito-identity-js` (CDN) — handles SRP authentication, sign-up, confirmation code verification, session management, and token refresh
* `fetch()` API — calls the REST API with the ID token in the `Authorization` header

The client stores Cognito session tokens in `localStorage` (managed by the SDK), so sessions persist across page refreshes.

## Deploy to a New Account / Region

### Step 1: Build

```bash
cd demo-1-notes-api
sam build
```

### Step 2: Deploy (first time — guided)

On the first deploy to a new account, use `--guided` to set the region and stack name interactively:

```bash
sam deploy --guided
```

SAM will prompt for:
- Stack name (default: `demo-1-notes-api`)
- AWS Region (choose your target region)
- Parameter `Environment` (default: `dev`)
- Confirm changeset (Y)
- Allow SAM CLI IAM role creation (Y)
- Save arguments to `samconfig.toml` (Y)

This creates a managed S3 bucket in the target account for deployment artifacts.

### Step 3: Update the client configuration

After deployment, SAM prints the stack outputs. Update the `CONFIG` object in `client/index.html` with your values:

```javascript
const CONFIG = {
  API_URL: '<ApiUrl output>',         // e.g. https://abc123.execute-api.us-east-1.amazonaws.com/dev
  USER_POOL_ID: '<UserPoolId output>', // e.g. us-east-1_AbCdEfGhI
  CLIENT_ID: '<UserPoolClientId output>' // e.g. 1abc2def3ghi4jkl5mno
};
```

You can retrieve these values at any time:

```bash
aws cloudformation describe-stacks --stack-name demo-1-notes-api \
  --query "Stacks[0].Outputs" --output table
```

### Step 4: Subsequent deploys

After the first guided deploy, `samconfig.toml` stores all settings. Just run:

```bash
sam build && sam deploy
```

## Test (CLI)

Update the region in the test script, then run:

```powershell
$env:AWS_REGION = "your-region"
$env:STACK_NAME = "demo-1-notes-api"
powershell -ExecutionPolicy Bypass -File test_api.ps1
```

Or on Linux/macOS:

```bash
export AWS_REGION=your-region
export STACK_NAME=demo-1-notes-api
bash test_api.sh
```

## Test (Browser)

Open `client/index.html` in a browser. Sign up with a real email address (you'll receive a verification code), confirm your account, sign in, and use the app.

## Cleanup

Remove all deployed resources:

```bash
sam delete --stack-name demo-1-notes-api
```

This deletes the CloudFormation stack and all resources it created (API Gateway, Lambda functions, DynamoDB table, Cognito User Pool, IAM roles). The SAM deployment S3 bucket is retained — delete it manually from the S3 console if desired.

