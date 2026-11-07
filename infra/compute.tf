# Latest official Ubuntu 24.04 LTS (Noble) AMI from Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  count      = var.ssh_public_key == "" ? 0 : 1
  key_name   = "${var.project_name}-admin"
  public_key = var.ssh_public_key
}

locals {
  app_src_dir = "${path.module}/.."
  image_uri   = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    registry     = split("/", aws_ecr_repository.app.repository_url)[0]
    image        = local.image_uri
    app_port     = var.app_port
    app_py       = filebase64("${local.app_src_dir}/app.py")
    dockerfile   = filebase64("${local.app_src_dir}/Dockerfile")
    requirements = filebase64("${local.app_src_dir}/requirements.txt")
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  key_name               = var.ssh_public_key == "" ? null : aws_key_pair.admin[0].key_name

  # Public IP gives outbound internet without a NAT gateway. Inbound is still
  # locked down by the app security group (ALB on app_port, one CIDR on 22).
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # +1 hop so the Docker container can reach IMDS
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20 # room for Docker images; the AMI itself is 8 GiB
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-app" }

  # Make sure the instance can actually pull from ECR on first boot.
  depends_on = [aws_iam_role_policy.ecr_pull]
}
