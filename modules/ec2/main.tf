locals {
  user_data = <<-EOF
            #!/bin/bash
            sudo apt-get -y update
            sudo apt-get -y install wget
            sudo wget https://get.docker.com -O docker_install.sh  
            sudo sh docker_install.sh
            sudo usermod -aG docker $USER
            sudo service docker restart
            sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            sudo apt-get -y install awscli

            EOF

}

resource "tls_private_key" "key_pair" {
  count     = var.ec2_key_name == "" ? 1 : 0
  algorithm = "RSA"
}

resource "aws_key_pair" "key_pair" {
  count = var.ec2_key_name == "" ? 1 : 0

  key_name   = "${var.name}-key"
  public_key = join("", tls_private_key.key_pair.*.public_key_openssh)

  tags = merge(
    { Name = "${var.name}.ssh-key" },
    var.tags
  )
}

resource "local_file" "ssh_private_key" {
  count = var.ec2_key_name == "" ? 1 : 0

  filename        = "${abspath(path.root)}/${var.name}-ssh-key.pem"
  file_permission = "0600"
  content         = join("", tls_private_key.key_pair.*.private_key_pem)
}

resource "local_file" "docker_compose" {
  filename        = "${path.module}/docker-compose.yaml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/docker-compose.yaml", {
    db_username        = var.db_username,
    db_password        = var.db_password,
    db_name            = var.db_name,
    ecr_registry_name  = var.ecr_registry_name
    ecr_registry_alias = var.ecr_registry_alias
    image_tag          = var.image_tag
  })
}


resource "aws_instance" "this" {
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.ec2_key_name == "" ? join("", aws_key_pair.key_pair[*].key_name) : var.ec2_key_name
  user_data_replace_on_change = true
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.vpc_security_group_ids
  user_data                   = local.user_data
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  provisioner "file" {
    source      = "${path.module}/docker-compose.yaml"
    destination = "/home/ubuntu/docker-compose.yaml"

    connection {
      type        = "ssh"
      user        = "ubuntu" # user for connection
      private_key = join("", tls_private_key.key_pair.*.private_key_pem)
      host        = self.public_ip
    }
  }

  tags = merge(
    { Name = var.instance_name },
    var.tags
  )
}

resource "aws_iam_role" "ssm" {
  name = "ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "ssm"
  role = aws_iam_role.ssm.name
}
