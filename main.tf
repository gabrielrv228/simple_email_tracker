terraform {
    backend "s3" {}
    required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "6.16.0"
        }
    }
}

provider "aws" {
  region = var.aws_region
}

# IAM role for Lambda execution
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "null_resource" "install_deps" {
  # Runs on every apply
  triggers = {
    run_at = timestamp()
  }

  provisioner "local-exec" {
    # Install dependencies 
    command = <<-EOT
      rm code.zip
      cd "${path.module}/code"
      python3 -m pip install -r requirements.txt --target . --upgrade
    EOT
  }
}

resource "aws_iam_role" "lambda_email_tracker" {
  name               = "lambda_email_tracker"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_email_tracker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Package the Lambda function code
data "archive_file" "lambda_package" {
  depends_on = [ null_resource.install_deps ]
  type        = "zip"
  source_dir  = "${path.module}/code"
  output_path = "${path.module}/code.zip"
}

# Lambda function
resource "aws_lambda_function" "email_tracker" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = "email_tracker"
  role             = aws_iam_role.lambda_email_tracker.arn
  handler          = "email_tracker.handler"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  runtime = "python3.11"

  environment {
    variables = {
      BOT_TOKEN = var.bot_token
      CHAT_ID   = var.chat_id
      PIXEL_IMG = var.pixel_img
    }
  }

  tags = {
    Environment = "production"
    Application = "email_tracker"
  }
}

resource "aws_lambda_function_url" "public_url" {
  function_name = aws_lambda_function.email_tracker.function_name
  authorization_type = "NONE"   

  cors {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["GET"]
    allow_origins     = ["*"]  
    expose_headers    = []
    max_age           = 86400
  }
}

output "lambda_url" {
    value = aws_lambda_function_url.public_url.function_url
}

# Optional: run a local (CI-side) invocation of the handler after deploy.
# This runs the helper Python script `code/invoke_local_handler.py` using the
# same environment where Terraform runs (for example the GitHub Actions runner).
resource "null_resource" "send_function_url" {
  # Re-run when the function URL changes
  triggers = {
    lambda_url = aws_lambda_function_url.public_url.function_url
  }

  depends_on = [ aws_lambda_function.email_tracker, aws_lambda_function_url.public_url ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      # Run the python invoker which imports and calls the handler
      python3 "${path.module}/code/invoke_local_handler.py" "Lambda ${aws_lambda_function.email_tracker.function_name} deployed successfully at URL ${aws_lambda_function_url.public_url.function_url}"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}