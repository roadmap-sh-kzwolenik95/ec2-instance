terraform {
  backend "s3" {
    bucket = "ec2-instance-roadmap"
    key    = "state/terraform.tfstate"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}

provider "acme" {
  alias      = "staging"
  server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

provider "acme" {
  alias      = "prod"
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "cloudflare_api_token" { sensitive = true }

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
