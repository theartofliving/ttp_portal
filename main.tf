provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "test" {
  ami           = "ami-01376101673c89611" # Replace with a valid Amazon Linux 2 AMI ID for your region
  instance_type = "t2.micro"

  tags = {
    Name = "web-instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "${file("index.html")}" > /var/www/html/index.html
              EOF
}

output "instance_public_ip" {
  value = aws_instance.test.public_ip
}
