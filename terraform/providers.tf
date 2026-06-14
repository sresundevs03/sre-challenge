provider "aws" {
  region  = var.aws_region
  profile = "sre-challenge"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner_email
      ManagedBy   = "terraform"
      ExpiryDate  = var.expiry_date
      Repository  = "github.com/sresundevs03/sre-challenge"
    }
  }
}
