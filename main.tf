provider "aws" {
  region = "us-east-1"  # Choose your region
}

# 1. VPC with Public and Private Subnets
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.0.0"

  name = "enterprise-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

# 2. Security Group for EC2
resource "aws_security_group" "ec2_security_group" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # In production, restrict this to trusted IPs for SSH
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "enterprise-ec2-sg"
  }
}

# 3. EC2 Instance
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI ID
  instance_type = "t3.micro"

  subnet_id         = module.vpc.public_subnets[0]
  security_groups   = [aws_security_group.ec2_security_group.name]
  key_name          = "your-ssh-key"  # Replace with your key
  associate_public_ip_address = true

  tags = {
    Name = "enterprise-web-instance"
  }

  # Block device (EBS volume)
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    delete_on_termination = true
  }
}

# 4. RDS (PostgreSQL)
resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "13.3"
  instance_class       = "db.t3.micro"
  name                 = "enterprise_db"
  username             = "admin"
  password             = "YourSecurePassword"  # Store in Secrets Manager in production
  parameter_group_name = "default.postgres13"
  publicly_accessible  = false
  multi_az             = true

  # Backup and encryption
  backup_retention_period = 7
  storage_encrypted       = true
  kms_key_id              = "your-kms-key-id"  # Replace with your KMS key ID

  db_subnet_group_name = aws_db_subnet_group.rds_subnet.id

  tags = {
    Name = "enterprise-postgres-db"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "enterprise-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "enterprise-rds-subnet-group"
  }
}

# 5. S3 Bucket with Encryption and Versioning
resource "aws_s3_bucket" "enterprise_bucket" {
  bucket = "enterprise-bucket-scotiabank"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "enterprise-bucket"
  }
}

# 6. CloudWatch for Monitoring
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/enterprise/application/logs"
  retention_in_days = 30

  tags = {
    Name = "enterprise-log-group"
  }
}

# 7. IAM Role for EC2 to Access S3 and CloudWatch
resource "aws_iam_role" "ec2_role" {
  name = "enterprise-ec2-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2_s3_cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"  # S3 Access

  # Add CloudWatch Full Access
}

# 8. Auto Scaling Group and Load Balancer (Optional)
module "autoscaling" {
  source                   = "terraform-aws-modules/autoscaling/aws"
  version                  = "5.0.0"
  
  name                     = "enterprise-autoscaling"
  max_size                 = 5
  min_size                 = 1
  desired_capacity         = 2

  vpc_zone_identifier      = module.vpc.private_subnets

  load_balancers           = [aws_lb.main.id]
  
  health_check_type        = "EC2"
}

module "lb" {
  source  = "terraform-aws-modules/elb/aws"
  version = "3.0.0"

  name = "enterprise-lb"

  subnets = module.vpc.public_subnets

  security_groups = [aws_security_group.ec2_security_group.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

