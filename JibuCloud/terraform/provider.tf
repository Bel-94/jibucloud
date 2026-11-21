provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "JibuCloud"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Workshop    = "KCA-AWS-SBG"
    }
  }
}
