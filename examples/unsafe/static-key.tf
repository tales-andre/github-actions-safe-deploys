# DELIBERATELY UNSAFE. Never apply. A deploy user with a long-lived access key: the kind of
# key that ends up pasted into GitHub secrets. scripts/check-no-static-keys.sh must reject it.

resource "aws_iam_user" "deploy" {
  name = "kettlebird-deploy-bot"
}

resource "aws_iam_access_key" "deploy" {
  user = aws_iam_user.deploy.name
}
