locals {
  full_domain = "${var.subdomain}.${var.apex-domain}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "my-machine" {
  key_name   = "my-machine-key"
  public_key = var.my-machine-pub-key
}

resource "aws_instance" "ubuntu_instance" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t4g.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ssh_access.id]
  key_name                    = aws_key_pair.my-machine.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # install nginx
    sudo apt update && sudo apt install -y nginx

    # signal that user_data script has finished
    touch /tmp/finished-user-data
  EOF

  tags = {
    Name = "ubuntu-nginx-server"
  }

  credit_specification {
    cpu_credits = "standard"
  }
}

data "http" "my_ip" {
  url = "http://checkip.amazonaws.com"
}

resource "aws_security_group" "ssh_access" {
  name_prefix = "ssh-access-"

  ingress {
    description = "Allow SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  ingress {
    description = "Allow HTTP from my All"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from my All"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "cloudflare_zone" "domain-zone" {
  name = var.apex-domain
}

resource "cloudflare_record" "url" {
  zone_id = data.cloudflare_zone.domain-zone.id
  name    = var.subdomain
  content = resource.aws_instance.ubuntu_instance.public_ip
  type    = "A"
  proxied = true
}

resource "acme_registration" "reg_staging" {
  provider      = acme.staging
  email_address = var.acme-email
}

resource "acme_certificate" "certificate" {
  provider = acme.staging

  account_key_pem = acme_registration.reg_staging.account_key_pem
  common_name     = local.full_domain

  dns_challenge {
    provider = "cloudflare"

    config = {
      CLOUDFLARE_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

resource "cloudflare_page_rule" "ssl-setting" {
  zone_id  = data.cloudflare_zone.domain-zone.id
  target   = "${local.full_domain}/*"
  priority = 1

  actions {
    ssl = "full"
  }
}

resource "null_resource" "nginx-configurator" {
  depends_on = [
    aws_instance.ubuntu_instance,
    acme_certificate.certificate
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.ubuntu_instance.public_ip
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "file" {
    content     = acme_certificate.certificate.certificate_pem
    destination = "/tmp/${local.full_domain}.crt.pem"
  }
  provisioner "file" {
    content     = acme_certificate.certificate.private_key_pem
    destination = "/tmp/${local.full_domain}.key.pem"
  }
  provisioner "file" {
    content = templatefile("${path.module}/site-config.tpl", {
      full_domain = local.full_domain
    })
    destination = "/tmp/${local.full_domain}"
  }
  provisioner "file" {
    source      = "${path.module}/site_files"
    destination = "/tmp/"
  }
  provisioner "remote-exec" {
    inline = [
      # wait for the user_data to finish
      "/bin/bash -c \"timeout 300 sed '/finished-user-data/q' <(tail -f /var/log/cloud-init-output.log)\"",
      # move cert and key to their destinations
      "sudo mv /tmp/${local.full_domain}.crt.pem /etc/ssl/certs/",
      "sudo chown root:root /etc/ssl/certs/${local.full_domain}.crt.pem",
      "sudo mv /tmp/${local.full_domain}.key.pem /etc/ssl/private/",
      "sudo chown root:root /etc/ssl/private/${local.full_domain}.key.pem",

      # configure Nginx
      "sudo mv /tmp/${local.full_domain} /etc/nginx/sites-enabled",
      "sudo chown root:root /etc/nginx/sites-enabled/${local.full_domain}",

      "sudo mkdir -p /var/www/${local.full_domain}/html/",
      "sudo mv /tmp/site_files/* /var/www/${local.full_domain}/html/",
      "sudo chown -R root:root /var/www/${local.full_domain}/html/",

      # reload Nginx config
      "sudo nginx -t && sudo systemctl reload nginx"
    ]
  }
}
