# Prerequisites:

### This project needs AWS account, domain on CloudFlare

Start with cloning the repo then:

1. github-OIDC provider must be configured in the AWS account, then IAM Role is needed to configure the trust between the git repo and the provider, an easy way to do that is to use the AWS CloudFormation template (slightly modified) from https://github.com/aws-actions/configure-aws-credentials, below are the commands that you can run create them, be aware that the GitHub OIDC provider can be created only once per account, thats why we set up the OIDCProviderArn variable using aws cli, you need to have aws cli credentials configured (SSO recomended)
    ```sh
    GitHubOrg='github-org'
    RepositoryName='repo-name'
    OIDCProviderArn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" --output text)

    aws cloudformation create-stack \
      --capabilities CAPABILITY_IAM \
      --stack-name "github-OIDC--${GitHubOrg}--${RepositoryName}" \
      --template-body file://cloudformation/configure-aws-credentials-latest.yml \
      --parameters \
          ParameterKey=GitHubOrg,ParameterValue="${GitHubOrg}" \
          ParameterKey=RepositoryName,ParameterValue="${RepositoryName}" \
          ParameterKey=OIDCProviderArn,ParameterValue="${OIDCProviderArn}"
    ```
2. S3 bucket for terraform backend, the CF template needs the role from previous step as an argument, this stack will create **ec2-instance-roadmap** bucket
    ```sh
    aws cloudformation create-stack \
      --stack-name "terraform-backend--${GitHubOrg}--${RepositoryName}" \
      --template-body file://cloudformation/terraform-backend.yaml \
      --parameters \
          ParameterKey=OIDCRoleStackName,ParameterValue="github-OIDC--${GitHubOrg}--${RepositoryName}"
    ```
3. CloudFlare **user token**: My Profile -> API Tokens -> Create Token, Token mush have these Permissions:
    1. Zone, Zone, Read
    2. Zone, Page Rules, Edit
    3. Zone, DNS, Edit
  
    In the Zone Resources, I have choosed: Include, Specic zone, \<my domain\>

4. Set **Repository secrets** in your github repo settings (Secrets and variables -> Actions -> Secrets tab)
    1. **CLOUDFLARE_API_TOKEN** -> CloudFlare user token (do not confuse with account owned token)
    2. **IAMROLE_GITHUB** -> IAM role arn created with the cloudformation stack github_OIDC
    3. **SSH_PRIV_KEY** -> private key PEM
5. Set **Repository variables** in your github repo settings (Secrets and variables -> Actions -> Variables tab)
    1. **ACME_EMAIL** -> email that will be used to request SSL certificate from LetsEncrypt
    2. **APEX_DOMAIN** -> domain that you own, like example.com
    3. **PUB_KEY** -> public ssh key that corresponds to the SSH_PROV_KEY
    4. **SUBDOMAIN** -> can be anything, this will become this part of the domain: **subdomain**.example.com

# Deploying the website
1. There is a GitHub Actions pipeline that will spin up needed infrastructure, configure it and deploy static files from **site_files** folder. Then on any push to main branch it will run the pipeline to deploy the files. The pipeline can also be run manually. It is also configured to run on schedule every month. 

    > LetsEncrypt certificates are valid maximum 90 days and the terraform resource *acme_certificate* [by default](https://registry.terraform.io/providers/vancluever/acme/latest/docs/resources/certificate#min_days_remaining-1) will renew it if the validity of certificate are 30 days remaining
2. Push new changes to the files int *site_files* directory and the pipeline will automatically update the website


# EC2 Instance roadmap.sh Challenge
This project fulfil requirements of the challenges and pushes for extra stretch goals
## Main goals:
1. EC2 instance of type *t4g.micro* will be created with the latest ubuntu LTS version. 
    > t4g.micro instance type is used because it is the latest generation and thus most cost effective if no free tier is avaliable
2. Security groups are configured in such way that ssh is only allowed for the current runner ip in time of pipeline execution
    ```tf
    data "http" "my_ip" {
      url = "http://checkip.amazonaws.com"
    }
    ```
    > This is acheived using terraform data source http

3. All other necessary ec2 configuration is done in terraform, the code is self explanatory
    ```tf
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
    ```
    > its worth mentioning that with *t4g.micro* **cpu_credits** are set to *unlimited* by default, which can generate extra costs

    > user_data script is using a little trick, its creating a file when the script is finished setting up the instance, it was needed to signal to other terraform provisioners that the instance is ready 
## Stretch goals
1. The domain is set up on CloudFlare and the project is configured to use subdomain
    > cloudflare terraform provider together with *user API token* is used to configure everything on the cloudflare side
2. In this case HTTPS is implemented on two sides, because the DNS set to proxied in CloudFlare, it handles the traffic between CloudFlare and the client, the LetsEncrypt certificate is used to handle the traffic between origin (nginx server) and the CloudFlare
    > Worth to mention that LetsEncrypt ACME production environment have pretty low [Rate limits](https://letsencrypt.org/docs/rate-limits/#certificate-issuance-limits) so when testing it is advised to use [LetsEncrypt ACME staging environment](https://letsencrypt.org/docs/staging-environment/)

    > Due to [how CloudFlare verify origin <-> CloudFlare SSL traffic](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/) when using LetsEncrypt Prod certificate it is advised to use **strict** mode, when using staging certificate **full** mode, [terraform docs on the ssl setting](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/page_rule#ssl-1)
    ```tf
    resource "cloudflare_page_rule" "ssl-setting" {
      zone_id  = data.cloudflare_zone.domain-zone.id
      target   = "${local.full_domain}/*"
      priority = 1
    
      actions {
        ssl = "strict"
      }
    }
    ```
    > I have configured two acme providers, one prod and one staging, modify the terraform code to switch
3. For the pipeline for the project I used GitHub Actions, it's already avaliable with GitHub repository and have readable pipeline syntax, it's easy to use with AWS and terraform
    > One job applies terraform and then uses rsync action to deploy the files

    > There is another job "Manual destroy Terraform" that will run terraform destroy and cleanup after testing the demo project. No forgotten resources should be left and incur any innecessary charges

## Example access Nginx access logs:
Log below demonstrates that requests that are coming from CloudFlare are done using https, all http request are redirects to the https (302 response code)
```
172.64.238.81 - - [27/Jan/2025:19:09:28 +0000] "GET / HTTP/1.1" 302 154 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "http"
162.158.123.137 - - [27/Jan/2025:19:09:28 +0000] "GET / HTTP/2.0" 304 0 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
172.64.236.120 - - [27/Jan/2025:19:09:42 +0000] "GET / HTTP/2.0" 200 421 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
172.64.236.93 - - [27/Jan/2025:19:09:42 +0000] "GET /favicon.ico HTTP/2.0" 404 123 "https://awsnginx.kzwolenik.com/" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
172.64.236.237 - - [27/Jan/2025:19:09:42 +0000] "GET /pexels-pixabay-45201.jpg HTTP/2.0" 200 412821 "https://awsnginx.kzwolenik.com/" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
162.158.122.103 - - [27/Jan/2025:19:09:50 +0000] "GET / HTTP/1.1" 302 154 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "http"
162.158.120.242 - - [27/Jan/2025:19:09:50 +0000] "GET / HTTP/2.0" 200 421 "-" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
162.158.120.148 - - [27/Jan/2025:19:09:51 +0000] "GET /favicon.ico HTTP/2.0" 404 123 "https://awsnginx.kzwolenik.com/" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
162.158.122.181 - - [27/Jan/2025:19:09:51 +0000] "GET /pexels-pixabay-45201.jpg HTTP/2.0" 200 412821 "https://awsnginx.kzwolenik.com/" "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0" "https"
```

Challenge link: https://roadmap.sh/projects/ec2-instance