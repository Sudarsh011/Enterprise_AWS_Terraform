provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "banking_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Public Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.banking_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
}

# Private Subnets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.banking_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.banking_vpc.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB (Load Balancer)
resource "aws_lb" "banking_alb" {
  name               = "banking-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet.id]
}

# EC2 Instances (Auto Scaling Group)
resource "aws_launch_template" "web_server" {
  name_prefix   = "web-server"
  image_id      = "ami-12345678"
  instance_type = "t3.medium"
  key_name      = "banking-key"
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.private_subnet.id]
  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }
}

# RDS Database (PostgreSQL)
resource "aws_db_instance" "banking_db" {
  engine             = "postgres"
  engine_version     = "13"
  instance_class     = "db.t3.medium"
  allocated_storage  = 20
  storage_encrypted  = true
  multi_az           = true
  username           = "admin"
  password           = "securepassword"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  publicly_accessible = false
  skip_final_snapshot = true
}

# S3 Bucket for Logging
resource "aws_s3_bucket" "banking_logs" {
  bucket = "banking-app-logs"
  acl    = "private"
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "banking_ec2_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "banking_logs" {
  name = "banking-app-logs"
  retention_in_days = 30
}

# CloudWatch Metric Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name        = "CPUUtilization"
  namespace         = "AWS/EC2"
  period           = 60
  statistic        = "Average"
  threshold        = 80
  alarm_description = "This alarm monitors high CPU utilization"
  alarm_actions    = []
}

# GuardDuty
resource "aws_guardduty_detector" "guardduty" {
  enable = true
}
