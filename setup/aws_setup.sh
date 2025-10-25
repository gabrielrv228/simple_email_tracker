#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

#AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
BUCKET_NAME="my-unique-bucket-123456789012"
BUCKET_REGION="us-east-1"
ROLE_NAME="AccessRole"
POLICY_NAME="AccessPolicy"

#GitHub
USERNAME_OR_ORGANIZATION="gabrielrv228"
REPOSITORY_NAME="email_tracker"
BRANCH_NAME="master"

ACTION="${1:-}" # usage: ./aws_setup.sh [create|destroy]


if [[ "$ACTION" != "create" && "$ACTION" != "destroy" ]]; then
  echo "❌ Invalid or missing action."
  echo "Usage: $0 [create|destroy]"
  exit 1
fi

echo "➡️ Running action: $ACTION"

# ============================================================
# HELPER FUNCTIONS
# ============================================================
function info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
function warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
function error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
function exists() { aws "$@" >/dev/null 2>&1; }

# ============================================================
# CREATE RESOURCES
# ============================================================
function create_resources() {
  info "Creating or verifying S3 bucket: $BUCKET_NAME"

  if exists s3api head-bucket --bucket "$BUCKET_NAME"; then
    warn "Bucket already exists. Skipping creation."
  else
      aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$BUCKET_REGION" 

    info "Bucket $BUCKET_NAME created."
  fi

  # ---- trust policy for EC2 initially --------------------------------
  cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  # ---- create or verify IAM role -------------------------------------
  if exists iam get-role --role-name "$ROLE_NAME"; then
    warn "Role $ROLE_NAME already exists. Skipping creation."
  else
    aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document file://trust-policy.json
    info "Role $ROLE_NAME created."
  fi

  # ---- permissions ----------------------------------------------------
  cat > permissions.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole"
      ],
      "Resource": "arn:aws:iam::*:role/${ROLE_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission",
        "lambda:CreateFunctionUrlConfig",
        "lambda:UpdateFunctionUrlConfig",
        "lambda:GetFunctionUrlConfig",
        "lambda:DeleteFunctionUrlConfig",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListVersionsByFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:GetFunctionCodeSigningConfig"
      ],
      "Resource": [
        "arn:aws:lambda:*:*:function:email_tracker"
      ]
    },
    {
      "Sid": "AllowLimitedIAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole"

      ],
      "Resource": "arn:aws:iam::*:role/lambda_email_tracker"
    },
    {
      "Sid": "AllowPassSpecificRoleToLambda",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/lambda_email_tracker",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "lambda.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF

  POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

  if exists iam get-policy --policy-arn "$POLICY_ARN"; then
    warn "Policy already exists. Skipping creation."
  else
    POLICY_ARN=$(aws iam create-policy \
      --policy-name "$POLICY_NAME" \
      --policy-document file://permissions.json \
      --query 'Policy.Arn' \
      --output text)
    info "Policy $POLICY_NAME created."
  fi

  # ---- attach policy --------------------------------------------------
  if exists iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "$POLICY_NAME"; then
    warn "Policy already attached to role."
  else
    aws iam attach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn "$POLICY_ARN"
    info "Attached policy $POLICY_NAME to $ROLE_NAME."
  fi

  # ---- update trust policy for GitHub OIDC ----------------------------
  cat > oidc-trust-policy.json <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":{"Federated":"arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"},
      "Action":"sts:AssumeRoleWithWebIdentity",
      "Condition":{
        "StringEquals":{
          "token.actions.githubusercontent.com:sub":"repo:${USERNAME_OR_ORGANIZATION}/${REPOSITORY_NAME}:ref:refs/heads/${BRANCH_NAME}",
          "token.actions.githubusercontent.com:aud":"sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document file://oidc-trust-policy.json

  info "Updated trust policy for GitHub OIDC."
  info "✅ Setup complete: $ROLE_NAME and $BUCKET_NAME ready."

  rm -f trust-policy.json permissions.json oidc-trust-policy.json
}

# ============================================================
# DESTROY RESOURCES
# ============================================================
function destroy_resources() {
  info "Destroying AWS resources..."
  
  POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

  # Detach policy from role
  if exists iam get-role --role-name "$ROLE_NAME"; then
    info "Detaching policies from role..."
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text || true)
    for arn in $ATTACHED_POLICIES; do
      aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$arn"
      info "Detached $arn"
    done

    aws iam delete-role --role-name "$ROLE_NAME"
    info "Deleted role $ROLE_NAME."
  else
    warn "Role $ROLE_NAME does not exist."
  fi

  # Delete policy
  if exists iam get-policy --policy-arn "$POLICY_ARN"; then
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    for version in $VERSIONS; do
      aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$version"
    done
    aws iam delete-policy --policy-arn "$POLICY_ARN"
    info "Deleted policy $POLICY_NAME."
  else
    warn "Policy $POLICY_NAME not found."
  fi

  # Empty and delete S3 bucket
  if exists s3api head-bucket --bucket "$BUCKET_NAME"; then
    info "Emptying and deleting S3 bucket $BUCKET_NAME..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive || true
    aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$BUCKET_REGION"
    info "Deleted bucket $BUCKET_NAME."
  else
    warn "Bucket $BUCKET_NAME not found."
  fi

  info "✅ Destruction complete."
}

# ============================================================
# MAIN LOGIC
# ============================================================
case "$ACTION" in
  create)
    create_resources
    ;;
  destroy)
    destroy_resources
    ;;
  *)
    error "Usage: $0 [create|destroy]"
    exit 1
    ;;
esac
