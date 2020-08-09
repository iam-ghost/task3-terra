provider "aws" {
  region  = "ap-south-1"
  profile = "iamkunal"
}

#creating network VPC
resource "aws_vpc" "myNetwork" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main"
  }
}

#creating a public subnet for web-server
resource "aws_subnet" "publicSubnet" {
    depends_on = [ 
        aws_vpc.myNetwork,
  ]

  vpc_id     = aws_vpc.myNetwork.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "publicSubnet"
  }
}

#creating a private subnet for database server
resource "aws_subnet" "privateSubnet" {
    depends_on = [
        aws_vpc.myNetwork,
    ]
  vpc_id     = aws_vpc.myNetwork.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "privateSubnet"
  }
}

#creating a internet gateway to dNAT for public subnet
resource "aws_internet_gateway" "gw" {
    depends_on = [
        aws_vpc.myNetwork,
    ]

  vpc_id = aws_vpc.myNetwork.id

  tags = {
    Name = "gw"
  }
}

#creating route table for public subnet
resource "aws_route_table" "r" {
    depends_on = [
        aws_vpc.myNetwork,
        aws_internet_gateway.gw
    ]
  vpc_id = aws_vpc.myNetwork.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "publicRoute"
  }
}

#associating public subnet to route table
resource "aws_route_table_association" "a" {
    depends_on = [
        aws_vpc.myNetwork,
        aws_subnet.publicSubnet,
        aws_route_table.r,
    ]
  subnet_id      = aws_subnet.publicSubnet.id
  route_table_id = aws_route_table.r.id
}

#creating_security_groups for web server
resource "aws_security_group" "firewall_public" {
    
     depends_on = [
        aws_vpc.myNetwork,
    ]

  name        = "firewall_public"
  description = "Allow TLS inbound traffic"
   vpc_id      = aws_vpc.myNetwork.id

  ingress {
    description = "HTTP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "firewall_public"
  }
}

#creating security group for database server
resource "aws_security_group" "firewall_private" {
 depends_on = [
        aws_vpc.myNetwork,
    ]

  name        = "firewall_private"
  description = "Allow subnet trafic for database"
  vpc_id      = aws_vpc.myNetwork.id

  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.myNetwork.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "firewall_private"
  }
}


#creating_keys
resource "tls_private_key" "infra_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}
resource "aws_key_pair" "infra_key" {
  key_name   = "infra_key"
  public_key = tls_private_key.infra_key.public_key_openssh
}
resource "local_file" "infra_key" {
  content = tls_private_key.infra_key.private_key_pem
  filename = "/root/terraform/infra_key.pem"
}

#launching_instances for webserver
resource "aws_instance" "wordpress" {
  depends_on = [
    aws_vpc.myNetwork,
    aws_subnet.publicSubnet,
    tls_private_key.infra_key,
    aws_key_pair.infra_key,
    local_file.infra_key,
    aws_security_group.firewall_public,
  ]

  ami           = "ami-03100b7790806a77e"
  instance_type = "t2.micro"
  key_name = "infra_key"
  vpc_security_group_ids = [ aws_security_group.firewall_public.id ]
  subnet_id = aws_subnet.publicSubnet.id
  
  
 
  tags = {
    Name = "Public server"
   }
}

#launching_instances for database
resource "aws_instance" "mySQL" {
    depends_on = [
    aws_vpc.myNetwork,
    aws_subnet.privateSubnet,
    tls_private_key.infra_key,
    aws_key_pair.infra_key,
    local_file.infra_key,
    aws_security_group.firewall_private,
  ]
  

  ami           = "ami-76166b19"
  instance_type = "t2.micro"
  key_name = "infra_key"
  vpc_security_group_ids = [ aws_security_group.firewall_private.id ]
  subnet_id = aws_subnet.privateSubnet.id
  
 
  tags = {
    Name = "Private server"
   }
}

resource "null_resource" "launch_portal"  {
  depends_on = [
    aws_instance.wordpress,
    aws_instance.mySQL,
  ]
  provisioner "local-exec" {
	    command = "chrome  ${aws_instance.wordpress.public_ip}"
  	}
}

output "aws_wordpress_ip" {
  value = aws_instance.wordpress.public_ip
}

output "aws_database_ip" {
  value = aws_instance.mySQL.private_ip
}