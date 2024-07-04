provider "aws" {
  region = "ap-south-1"
}

variable "aws_region" {
  default = "ap-south-1"
}

# Reference Existing S3 Bucket
data "aws_s3_bucket" "my_bucket" {
  bucket = "ttp-portal-bucket"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda to access S3 and OpenSearch
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy_opensearch_s3"
  description = "Policy for Lambda to access S3 and OpenSearch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          data.aws_s3_bucket.my_bucket.arn,
          "${data.aws_s3_bucket.my_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = "ec2:CreateNetworkInterface"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = "ec2:AttachNetworkInterface"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = "ec2:DeleteNetworkInterface"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = "ec2:DescribeNetworkInterfaces"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = "ec2:DetachNetworkInterface"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach Policy to IAM Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "my_lambda" {
  function_name = "my_lambda_function"
  filename      = "lambda_function.zip" # Ensure the ZIP file is in the same directory
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    subnet_ids         = ["subnet-01c69faaddc508e80"]  # Replace with your subnet IDs
    security_group_ids = ["sg-06f06a3d0ba303ce3"]      # Replace with your security group IDs
  }
  environment {
    variables = {
      OPENSEARCH_ENDPOINT = "https://vpc-ttpportal-lrysnolxf3dtvnwgchv3xln2py.ap-south-1.es.amazonaws.com"
      REGION              = "ap-south-1"
    }
  }
}

# S3 Bucket Notification for Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = data.aws_s3_bucket.my_bucket.bucket
  lambda_function {
    lambda_function_arn = aws_lambda_function.my_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "my_api" {
  name = "MyAPI"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "mylambda"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.my_lambda.invoke_arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "my_distribution" {
  enabled = true

  origin {
    domain_name = data.aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = "S3-myBucket"
  }

  origin {
    domain_name = "${aws_api_gateway_rest_api.my_api.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "APIGateway-myAPI"
  }

  default_cache_behavior {
    target_origin_id       = "S3-myBucket"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "APIGateway-myAPI"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "POST"]
    cached_methods         = ["GET", "HEAD"]
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.my_distribution.domain_name
}
