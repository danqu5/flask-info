# Flask /info on AWS: Terraform + GitHub Actions

Terraform in `infra/` provisions the infrastructure. `.github/workflows/deploy.yml` builds and deploys the app.

- A VPC with two public subnets in different AZs (an ALB needs two)
- An **Application Load Balancer** that listens on HTTP :80 and forwards to the instance on :5000 (health check `GET /info`)
- One **EC2 instance** (Ubuntu 24.04 LTS) that runs the app container on boot through a systemd unit. ECR login uses `amazon-ecr-credential-helper` with the instance role, so no credentials are stored on the box. SSH user: `ubuntu`.
- An **ECR repository** for the image
- An **IAM role** for the instance and an **IAM user** for the pipeline, each with minimal permissions

```
Internet ──:80──▶ ALB (alb-sg) ──:5000──▶ EC2 (app-sg) ──▶ docker: flask app
                                 SSH :22 ◀── ssh_allowed_cidr only
```

## Security choices

| Requirement | How it's met |
|---|---|
| Port 80 open on the ALB | `alb-sg` allows TCP 80 from `0.0.0.0/0`. Its egress is limited to port 5000 toward `app-sg`. |
| SSH restricted | `app-sg` allows TCP 22 from `ssh_allowed_cidr` only (default `1.2.3.4/32`). Validation rejects `0.0.0.0/0`. |
| App port reachable only from the ALB | `app-sg` allows 5000 only from `alb-sg`, by security-group reference. Hitting the instance's public IP on :5000 times out. |
| Minimal IAM | Instance role: pull from **this ECR repository only**, plus the SSM agent permissions Run Command needs. Pipeline user: push to this repository, and run `AWS-RunShellScript` only on instances tagged `Project=<project_name>`. |
| Container on boot | `docker.service` and `app.service` are both enabled in systemd, with `Restart=always`. |
| Also | IMDSv2 required, encrypted root volume, ALB drops invalid headers, ECR scan on push, lifecycle policy keeps 10 images. |

**App change:** the provided `app.py` read instance metadata without a token (IMDSv1). That fails when IMDSv2 is required. It now gets a session token first, and falls back to IMDSv1 if no token is available. The JSON response is unchanged.

## AWS credentials

Both Terraform and the pipeline authenticate with **AWS access keys**. Nothing is hardcoded.

- **Terraform:** export the keys of an IAM user that can create the resources. `AdministratorAccess` works, or attach `infra/terraform-deployer-policy.json` for tighter scope.
  ```bash
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  ```
- **GitHub Actions:** Terraform creates a least-privilege IAM user (`<project_name>-github-ci`) and its access key. Put those keys in the repository's **secrets** (*Settings → Secrets and variables → Actions*):

  | Secret | Value |
  |---|---|
  | `AWS_ACCESS_KEY_ID` | `terraform output -raw ci_access_key_id` |
  | `AWS_SECRET_ACCESS_KEY` | `terraform output -raw ci_secret_access_key` |

  Optional repository **variables**: `AWS_REGION` (default `us-east-2`) and `PROJECT_NAME` (default `flask-info`, must match Terraform's `project_name`).

  Or set them with the [GitHub CLI](https://cli.github.com/) (after `gh auth login`), from `infra/`. The keys go straight from Terraform to GitHub without being shown:
  ```bash
  REPO=owner/repo
  terraform output -raw ci_access_key_id     | gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO"
  terraform output -raw ci_secret_access_key | gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO"
  gh variable set AWS_REGION --repo "$REPO" --body us-east-2   # match Terraform's aws_region
  gh secret list --repo "$REPO"   # check
  ```

  After a `terraform destroy` and re-apply, the pipeline user gets a new access key, so set the two secrets again.

The pipeline user's secret key is stored in Terraform state, which is gitignored. Keep the state file private.

## Deploy the infrastructure

```bash
cd infra
terraform init
terraform apply -var ssh_allowed_cidr="$(curl -s https://checkip.amazonaws.com)/32"
# optional: -var aws_region=us-west-2  -var ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

curl "$(terraform output -raw app_url)"
```

The target usually turns healthy **2–4 minutes** after apply finishes. On first boot ECR is still empty, so the instance builds the image from the app source passed in through user data. After that it pulls from ECR.

Tear down: `terraform destroy`. The ECR repository is set to `force_delete`, so destroy works even when it holds images.

## CI/CD (GitHub Actions)

The workflow runs on every push to `main` that touches the app, and can also be started manually (**Actions → Build and deploy → Run workflow**), or from the terminal:

```bash
gh workflow run deploy.yml --repo owner/repo
gh run watch --repo owner/repo
```

1. **Build** the image and **push** it to ECR, tagged with the commit SHA and `latest`
2. **Find** the instance by tag (`Project=<project_name>`), so there are no IDs to copy out of Terraform
3. **Deploy** with **SSM Run Command**: pull the new SHA-tagged image (stopping if that fails, before anything changes), pin that tag in `/etc/app.env`, `systemctl restart app`, then check `localhost/info`
4. **Smoke-test**: wait for the ALB target to be healthy, then `curl http://<alb>/info`

SSM is used instead of SSH because GitHub-hosted runners have changing IP addresses. Deploying over SSH would mean opening port 22 to the internet. To roll back, re-run the workflow for an older commit.

With a single instance, a deploy causes a few seconds of 502s while the container restarts.

## Notes and trade-offs

- **No NAT gateway.** The instance sits in a public subnet with a public IP so it can reach ECR and package repositories without paying for NAT (~$32/month). Inbound access is still limited by `app-sg`. In production I'd use private subnets with NAT or VPC endpoints, and drop the SSH rule.
- **HTTP only**, as specified. Adding HTTPS means an ACM certificate and a :443 listener.
- **Single instance.** It can be swapped for an Auto Scaling group with a launch template, using the same user data.
- **State is local.** For a team, add an S3 backend (with locking).
