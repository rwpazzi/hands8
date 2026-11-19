provider "aws" {
  region = "us-east-1"
}

##################################
# Get Ubuntu 26.04 AMI
##################################
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

##################################
# Key Pair (must exist locally)
##################################
resource "aws_key_pair" "default" {
  key_name   = "terra_key"
  public_key = file("~/.ssh/key1.pub")
}

####### STEP 2 #########

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "handson8-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "handson8-igw"
  }
}

# Create a public subnet (for the Web server)
resource "aws_subnet" "public" {
  vpc_id                        = aws_vpc.main.id
  cidr_block                    = "10.0.1.0/24"
  map_public_ip_on_launch       = true
  availability_zone             = "us-east-1a"

  tags = {
    Name = "public-subnet"
  }
}

# Private subnet for WB server
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet"
  }
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}


##################################
# Security Group (SSH, HTTP)
##################################
resource "aws_security_group" "web_sg" {
  name   = "web_sg"

  vpc_id = aws_vpc.main.id  #ADDED THIS

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
    from_port   = 3306
    to_port     = 3306
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

# Sec group for DB server
resource "aws_security_group" "db_sg" {
  name = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow 3306"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-sg"
  }
}


##################################
# EC2: Web Server (Apache) in the public subnet
##################################
resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  key_name               = aws_key_pair.default.key_name
  subnet_id              = aws_subnet.public.id  # ADDED THIS


  user_data = <<-EOF
                #!/bin/bash
                apt update -y
                apt install -y apache2 mysql-client
                systemctl enable apache2
                systemctl start apache2
                echo "<h1>Welcome to INFR2670 Web server!!!</h1>" > /var/www/html/index.html
                EOF

  tags = {
    Name = "web-server"
  }
}

##################################
# EC2: DB Server (MySQL)
##################################
resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.db_sg.id] # CHANGED TO db_sg
  associate_public_ip_address = false # CHANGED TO FALSE
  key_name               = aws_key_pair.default.key_name
  subnet_id = aws_subnet.private.id  #ADDED THIS

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              apt update -y
              DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
              sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
              systemctl enable mysql
              systemctl restart mysql
              mysql -e "CREATE USER IF NOT EXISTS 'webapp'@'%' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'webapp'@'%' WITH GRANT OPTION;"
              mysql -e "FLUSH PRIVILEGES;"
              EOF

  tags = {
    Name = "db-server"
  }
}

##################################
# Outputs (public IPs)
##################################
output "Web_server_public_ip" {
  value = aws_instance.web.public_ip
}

output "DB_server_public_ip" {
  value = aws_instance.db.public_ip
}

output "DB_server_private_ip" {
  value = aws_instance.db.private_ip
}
