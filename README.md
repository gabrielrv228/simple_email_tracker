
# Email Tracker (Lambda tracking pixel)

Small serverless project that provides a 1x1 tracking pixel served by an AWS Lambda function. When the pixel URL is loaded (for example, when an email is opened), the Lambda function sends a notification to a Telegram chat and returns a base64-encoded image.

This repo includes Terraform to provision the Lambda, an example HTML snippet to embed in emails, a helper AWS setup script, and the Lambda source code.

## Contents

- `main.tf` - Terraform configuration that packages and deploys the Lambda, creates an IAM role and function URL.
- `variables.tf` - Terraform variables used by the deployment (Telegram bot token, chat id, pixel image, region).
- `code/` - Lambda function source and dependencies.
	- `email_tracker.py` - Lambda handler. Reads query string parameters and sends messages to Telegram.
	- `requirements.txt` - Python dependencies installed into the Lambda package.
- `html.html` - Example tracking-pixel HTML snippet to embed in messages.
- `setup/aws_setup.sh` - Helper script to create some AWS resources (S3 bucket, IAM role/policy) used by CI/workflows or local setup.
- `.github/workflows/deploy.yaml` - GitHub Action workflow to run Terraform using OIDC/assumed role.

## How it works (high level)

1. An email contains an image tag pointing to the Lambda Function URL with query parameters (for example `?em=user@example.com`). See `html.html`.
2. When the email client loads the image, AWS invokes the Lambda via the function URL.
3. The Lambda (`email_tracker.handler`) extracts query parameters, calls the Telegram Bot API to notify you, and returns the provided base64 image as the HTTP response (image/png, base64-encoded).

## Prerequisites

- A GitHub repository with Actions enabled (this project is designed to deploy only via the included GitHub Actions workflow).
- AWS account where resources will be created. The repository includes `setup/aws_setup.sh` which bootstraps the S3 backend, IAM roles and policies required by the workflow — the script must be run by a user or role with permissions to create these resources (administrator-level or an equivalent permission set).
- A Telegram Bot token and a chat ID where the bot can post messages. These are configured as GitHub Actions variables/secrets (see below).

## Configuration

This project is intended to be deployed exclusively through the GitHub Actions workflow (`.github/workflows/deploy.yaml`). Terraform and dependency packaging are executed inside the CI environment; you should not run `terraform apply` locally for deployment.

The Terraform variables you must provide (via GitHub repository/organization Variables and Secrets) are:

- `bot_token` - Telegram bot token (string) — store as a secret
- `chat_id` - Telegram chat id where notifications are sent (string) — secret or variable
- `pixel_img` - Base64-encoded PNG (or other image) that will be returned by the Lambda — secret or variable
- `aws_region` - AWS region (defaults to `us-east-1` if not set)

Set those values in the repository (or organization) Settings → Secrets and variables → Actions → Variables. The workflow maps them to `TF_VAR_*` environment variables when it runs.

## Bootstrapping AWS resources for GitHub Actions (setup/aws_setup.sh)

This repository includes `setup/aws_setup.sh`, a helper script that creates AWS resources used by the GitHub Actions pipeline (for example an S3 bucket for the Terraform backend and IAM roles/policies your runner will assume). Important notes:

- The script must be run with an AWS identity that has administrative privileges or equivalent permissions to create S3 buckets, IAM roles/policies, and attach policies. In practice this means an IAM user/role with AdministratorAccess or a custom policy that allows the same set of operations the script performs.
- Before running, edit the top of `setup/aws_setup.sh` and set values for `BUCKET_NAME`, `BUCKET_REGION`, `ROLE_NAME`, `POLICY_NAME`, and the GitHub repo values. These are necessary to allow the GitHub actions pipeline to use the role, execution will fail if they do not match. The script currently contains placeholder values and will try to create resources with those names.
- The script supports two actions:

```bash
chmod +x setup/aws_setup.sh
# create required resources
./setup/aws_setup.sh create

# destroy resources (clean up)
./setup/aws_setup.sh destroy
```

- The script uses the AWS CLI credentials available in your environment. To run as a specific profile:

```bash
AWS_PROFILE=your-admin-profile ./setup/aws_setup.sh create
```

- The `create` action will output or configure resources that you must wire into GitHub repository or organization variables. The GitHub Actions workflow (`.github/workflows/deploy.yaml`) expects the following repository or organization variables to be set in your GitHub settings:

	- `TERRAFORM_ROLE_ARN` — the ARN of the role GitHub Actions will assume (OIDC) to run Terraform
	- `S3_BUCKET_NAME` — the S3 bucket used as the Terraform backend
	- `S3_BUCKET_KEY` — backend state key/path
	- `S3_BUCKET_REGION` — region of the backend bucket
	- `BOT_TOKEN`, `CHAT_ID`, `PIXEL_IMG`, `AWS_REGION` — Terraform variables used during the workflow (sensitive values should be stored as GitHub secrets/variables)

Set those values in the repository (or organization) Settings → Secrets and variables → Actions → Variables (or Secrets for sensitive values). The workflow reads them and passes them to `terraform` via `TF_VAR_*` environment variables.

Security reminder: because the script creates IAM roles and policies that grant broad permissions, run it only from a trusted, secure environment and rotate any credentials/roles you create according to your security policies.
```

## Deployment (GitHub Actions only)

This project is designed to be deployed exclusively through the included GitHub Actions workflow at `.github/workflows/deploy.yaml`. The workflow initializes Terraform, installs dependencies, packages the Lambda code, and applies the Terraform configuration in a CI environment using an assumed role (OIDC). Do not run `terraform apply` locally for production deployment.

To deploy:

1. Run `./setup/aws_setup.sh create` (using an admin-capable AWS identity) to create the S3 backend bucket and IAM roles/policies used by the workflow.
2. Set the required repository/organization Variables and Secrets in GitHub (see the Bootstrapping section for the exact names).
3. From the Actions tab, run the `Deploy Email Tracker` workflow and choose `apply` (or `destroy`).

After the workflow completes successfully it will output the `lambda_url` which you can use in your email HTML snippet.

## Example HTML snippet

Replace `{lambda_link}` and `{target_email}` with your values (or generate the URL programmatically):

```html
<img src="https://{lambda_link}/?em={target_email}">
```

You can add the info and the Lambda will include the text in the Telegram notification.

## Code notes

- `code/email_tracker.py` reads the `BOT_TOKEN`, `CHAT_ID`, and `PIXEL_IMG` from environment variables configured by Terraform.
- It expects the Lambda to be invoked via a Function URL and reads `queryStringParameters` for `em` (email) and optional `info`.
- The handler returns a JSON response with `isBase64Encoded: true` and the `pixel_img` base64 body so AWS returns a valid image.


