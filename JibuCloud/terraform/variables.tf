variable "aws_region" {
  description = "AWS Region for the workshop."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Short environment name used in resource names."
  type        = string
  default     = "workshop"
}

variable "notification_email" {
  description = "Email address that will receive assignment notifications. Confirm the SNS subscription after apply."
  type        = string

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.notification_email))
    error_message = "Enter a valid email address."
  }
}

variable "name_prefix" {
  description = "Short prefix for JibuCloud resources."
  type        = string
  default     = "jibucloud"
}
