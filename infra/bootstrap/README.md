# State bootstrap

Every stack under `infra/live/aws` keeps its state in S3. That bucket has to
exist before any of those stacks can run `init`, so it cannot be created by
them. This is the chicken-and-egg problem: the backend can't manage itself.

This directory breaks the loop. It is plain Terraform with **local state**,
applied once per AWS account:

```bash
cd infra/bootstrap
terraform init
terraform apply -var account_id=111111111111 -var region=eu-west-1
```

It creates:

| Resource | Why |
|---|---|
| S3 bucket `cpb-tfstate-<account>-<region>` | Remote state. The name matches `infra/live/root.hcl`. |
| Versioning, plus a 90-day expiry for old versions | Lets you roll back a bad or corrupted state write. |
| SSE-KMS with a dedicated, rotating CMK | State holds secrets such as generated passwords and endpoints. |
| Public access block and `BucketOwnerEnforced` | State is never public, and ACLs are disabled. |
| Bucket policy denying non-TLS requests | Blocks plaintext access, even from callers with credentials. |
| `prevent_destroy` | Stops a stray `terraform destroy` from deleting every environment's state. |

## Why there is no DynamoDB lock table

Terraform 1.10 added S3-native locking (`use_lockfile = true`). It writes a
`.tflock` object next to the state with a conditional PUT. That replaces the
DynamoDB table (now deprecated for this purpose), so there is one less
resource to create, pay for and grant IAM on. `root.hcl` therefore requires
Terraform >= 1.10.

## What to do with this stack's own state

The resulting `terraform.tfstate` is small and holds no secrets. Either:

- commit nothing and keep it somewhere safe (a password manager or an
  encrypted share), or
- after the first apply, add a `backend "s3"` block pointing at the bucket it
  just created and run `terraform init -migrate-state` to move the state in.

If the local state is lost, nothing breaks. `terraform import` brings the
bucket back under management.

## Azure

The AKS stack stores its state in an Azure Storage account and uses Entra ID
auth, so no access keys are involved. Create it once with the CLI:

```bash
az group create -n rg-cpb-tfstate -l westeurope
az storage account create -n cpbtfstate<unique> -g rg-cpb-tfstate \
  --sku Standard_ZRS --min-tls-version TLS1_2 --allow-blob-public-access false \
  --allow-shared-key-access false
az storage container create -n tfstate --account-name cpbtfstate<unique> --auth-mode login
```

Then set `state_storage_account` in `infra/live/azure/dev/env.hcl`.
