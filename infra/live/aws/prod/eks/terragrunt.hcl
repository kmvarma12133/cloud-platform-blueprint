# prod eks. Shared settings: infra/live/_envcommon/aws-eks.hcl; values: ../env.hcl.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path = "${get_repo_root()}/infra/live/_envcommon/aws-eks.hcl"
}
