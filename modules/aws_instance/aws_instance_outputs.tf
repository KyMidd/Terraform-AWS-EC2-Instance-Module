##
# Outputs are used to expose computed values to other modules
# https://www.terraform.io/docs/configuration/outputs.html
##

output "aws_iam_role_id" {
  value = aws_iam_role.iam_role[*].id
}
output "aws_iam_role_name" {
  value = aws_iam_role.iam_role[*].name
}
output "aws_instance_id" {
  value = aws_instance.aws_instance[*].id
}
