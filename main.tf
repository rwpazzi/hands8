provider "aws" {
  region = "us-east-1"
}

##################################
# Get Ubuntu 24.04 AMI
##################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}


##################################
# Key Pair (must exist locally)
##################################
resource "aws_key_pair" "default" {
  key_name   = "terraform-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

##################################
# Security Group (SSH, HTTP)
##################################
resource "aws_security_group" "web_sg" {
  name   = "web_sg"

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

##################################
# EC2: Web Server (Apache)
##################################
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  key_name               = aws_key_pair.default.key_name

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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  key_name               = aws_key_pair.default.key_name

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

