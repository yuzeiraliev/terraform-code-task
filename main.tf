
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.23.1"
    }
  }
}

provider "aws" {
  region = "us-east-1" 
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  count = 2
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false
}

# Create nat_gateway
resource "aws_nat_gateway" "nat" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.private_subnet.id

  tags = {
    Name = "NAT"
  }
  depends_on = [aws_internet_gateway.example]
}

# Create a security group
resource "aws_security_group" "web_sg" {
  name_prefix = "web-"
  vpc_id     = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 8080
    to_port     = 8080
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


# Create an EC2 instance in the private subnet
resource "aws_instance" "web_instance" {
  ami           = "ami-0c875b10bc59b1fbd"
  instance_type = "t2.micro" 
  subnet_id     = aws_subnet.private_subnet.id
  
  security_groups = [aws_security_group.web_sg.id]

}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet[0].id, aws_subnet.public_subnet[1].id]
  security_groups     = [aws_security_group.web_sg.id]

  enable_deletion_protection = false

  enable_http2 = true

  
}

# Create a target group for the ALB
resource "aws_lb_target_group" "web_target_group" {
  name        = "web-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.my_vpc.id
}

# Create target group attachment
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.web_target_group.arn
  target_id        = aws_instance.web_instance.id
  port             = 80
}

# Create a listener rule for the ALB
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port             = 80
  protocol         = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_target_group.arn
  }
}

# Create route tables
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "Private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
  tags = {
    Name = "Public"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet[0].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet[1].id
  route_table_id = aws_route_table.public.id
}

