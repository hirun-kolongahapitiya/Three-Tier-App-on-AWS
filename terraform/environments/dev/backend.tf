####################################################################
# Remote state (optional).
#
# Left commented out so `terraform init` works locally without extra setup.
# To enable: create an S3 bucket and DynamoDB lock table you own (either
# with a small bootstrap TF run or via the AWS CLI), uncomment the block
# below, and replace the bucket / table names with yours.
####################################################################

# terraform {
#   backend "s3" {
#     bucket         = "your-tfstate-bucket"
#     key            = "todoapp/dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "your-tfstate-locks"
#     encrypt        = true
#   }
# }
