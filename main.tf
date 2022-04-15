provider "aws" {
  region  = "eu-central-1"
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

data "aws_subnet" "snet" {
  id = var.subnet_id
}

resource "aws_ecr_repository" "ecr" {
  name = "${var.user_prefix}-repository-terra"
}

data "aws_iam_policy_document" "assume_role_task" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.user_prefix}-execution-task-role-terra"
  assume_role_policy = data.aws_iam_policy_document.assume_role_task.json
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.user_prefix}-cluster-terra"
}

resource "aws_security_group" "ecs_sg" {
  name = "${var.user_prefix}-sg-terra"  
  vpc_id = data.aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "${var.user_prefix}-role-ecs-agent-terra"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "${var.user_prefix}-ecs-agent-terra"
  role = aws_iam_role.ecs_agent.name
}

resource "aws_launch_template" "ecs_launch_template" {
  name_prefix                 = "${var.user_prefix}-"
  image_id                    = "${var.ami_id}"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_agent.name
  }
  user_data                   = base64encode("#!/bin/bash\n mkdir -p /etc/ecs\n printf \"ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name}\\n\" >> /etc/ecs/ecs.config")
  instance_type               = "t2.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.ecs_sg.id]
  }
  key_name = "${var.user_prefix}-key-pair"
  tag_specifications {
    resource_type = "instance"

    tags = {
        Name = "${var.user_prefix}-instance-terra"
    }
  }
}

resource "aws_autoscaling_group" "asg" {
  name                 = "${var.user_prefix}-asg-terra"
  vpc_zone_identifier  = [data.aws_subnet.snet.id]
  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  desired_capacity          = 1
  min_size                  = 0
  max_size                  = 5
  health_check_grace_period = 300
  health_check_type         = "EC2"
}

resource "aws_ecs_task_definition" "task_definition" {
  family             = "${var.user_prefix}-task-definition-terra"
  cpu                = "512"
  memory             = "256"
  execution_role_arn = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn      = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = jsonencode([
    {
      name      = "${var.user_prefix}-container-terra"
      image     = "${aws_ecr_repository.ecr.repository_url}:latest"
      cpu       = 512
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "service" {
  name                    = "${var.user_prefix}-service-terra"
  cluster                 = aws_ecs_cluster.ecs_cluster.id
  task_definition         = aws_ecs_task_definition.task_definition.arn
  desired_count           = 1
  enable_ecs_managed_tags = true
  launch_type             = "EC2"
  deployment_controller {
      type = "ECS"
  }
  deployment_minimum_healthy_percent = 0
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
