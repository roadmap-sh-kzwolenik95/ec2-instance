# Prerequisites:

1. github-OIDC provider must be configured in the AWS account, then IAM Role is needed to configure the trust between the git repo and the provider, an easy way to do that is to use the AWS CloudFormation template from https://github.com/aws-actions/configure-aws-credentials, below are the commands that you can run create them, be aware that the GitHub OIDC provider can be created only once per account, thats why we set up the OIDCProviderArn variable using aws cli, you need to have aws cli credentials configured (SSO recomended)
```sh
GitHubOrg='github-org'
RepositoryName='repo-name'
OIDCProviderArn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" --output text)

aws cloudformation create-stack \
  --capabilities CAPABILITY_IAM \
  --stack-name "github-OIDC--${GitHubOrg}--${RepositoryName}" \
  --template-body file://configure-aws-credentials-latest.yml \
  --parameters \
      ParameterKey=GitHubOrg,ParameterValue="${GitHubOrg}" \
      ParameterKey=RepositoryName,ParameterValue="${RepositoryName}" \
      ParameterKey=OIDCProviderArn,ParameterValue="${OIDCProviderArn}"
```

Challenge link: https://roadmap.sh/projects/ec2-instance