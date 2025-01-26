variable "my-machine-pub-key" {
  description = "SSH public keys to connect to the EC2 instance"
  type        = string
  validation {
    condition     = can(regex("^ssh-rsa\\s+[A-Za-z0-9+/=]+\\s*", var.my-machine-pub-key))
    error_message = "Each SSH key must be in the correct format (e.g., ssh-rsa)."
  }
}
variable "apex-domain" {
  description = "Domain registered in CloudFlare"
  type        = string
}
variable "subdomain" {
  type = string
}
variable "acme-email" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.acme-email))
    error_message = "The provided value is not a valid email address. Please enter a valid email (e.g., example@example.com)."
  }
}
variable "pvt_key" {
  description = "Private key pem"
  type        = string
  validation {
    condition     = can(regex("^-----BEGIN RSA PRIVATE KEY-----(.|\n)*-----END RSA PRIVATE KEY-----$", var.pvt_key))
    error_message = "The provided value is not a valid PEM, must start with '-----BEGIN RSA PRIVATE KEY-----' and end with '-----END RSA PRIVATE KEY-----'"
  }
  sensitive = true
}
