config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# The AWS ruleset is added in Phase 13, pinned to a release:
# plugin "aws" {
#   enabled = true
#   version = "x.y.z"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
