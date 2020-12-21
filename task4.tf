provider "aws" {
  region = "ap-south-1"
  profile = "richie"
  access_key = var.access_key
  secret_key = var.secret_key
}



resource "aws_vpc" "MyNatVpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "nat_vpc"
  }
}


resource "aws_subnet" "Natsub_private" {
  vpc_id     = aws_vpc.MyNatVpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "nat_private_sub"
  }
}


resource "aws_subnet" "Natsub_public" {
  vpc_id     = aws_vpc.MyNatVpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "nat_public_sub"
  }
}

#Internet Gateway
resource "aws_internet_gateway" "MyIngateway" {
  vpc_id = aws_vpc.MyNatVpc.id

  tags = {
    Name = "Internetgateway"
  }
}

#Creaton of Routing table and associating it with our Internet Gateway
resource "aws_route_table" "MyNatroute" {
  depends_on = [aws_internet_gateway.MyIngateway, ]
  vpc_id = aws_vpc.MyNatVpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.MyIngateway.id
  }

  tags = {
    Name = "RoutingTable"
  }
}

resource "aws_route_table_association" "route_resource" {
  depends_on = [ aws_route_table.MyNatroute, ]
  subnet_id      = aws_subnet.Natsub_public.id
  route_table_id = aws_route_table.MyNatroute.id
}

# To get one static IP for NAT Gateway

resource "aws_eip" "NAT" {
	vpc	= true
}


# NAT Gateway creation
resource "aws_nat_gateway" "my_natgateway" {
  allocation_id = aws_eip.NAT.id
  subnet_id     = aws_subnet.Natsub_public.id

  tags = {
    Name = "gw NAT"
  }
  depends_on = [aws_internet_gateway.MyIngateway]
}

# Creating routing table for NAT Gateway
resource "aws_route_table" "Nat_Routing_Table" {
	vpc_id	= aws_vpc.MyNatVpc.id
	route {
		cidr_block	= "0.0.0.0/0"
		nat_gateway_id	= aws_nat_gateway.my_natgateway.id
	}
	tags = {
		Name = "routetablenatgateway"
	}
}

#To associate it with private subnet
resource "aws_route_table_association" "routeprivate" {
  subnet_id      = aws_subnet.Natsub_private.id
  route_table_id = aws_route_table.Nat_Routing_Table.id
}

#Security group for wordpress os
resource "aws_security_group" "sg_for_natwp" {
  name        = "allow_wp"
  description = "Allow ssh and http"
  vpc_id      = aws_vpc.MyNatVpc.id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
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
    Name = "wpsecgrp"
  }
}

#Security group for MySQL database
resource "aws_security_group" "sg_for_natsql" {
  name        = "allow_mysql"
  description = "Allow wordpress to MySQL"
  vpc_id      = aws_vpc.MyNatVpc.id

  ingress {
    description = "mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.sg_for_natwp.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sqlsecgrp"
  }
}

# To launch instance for wordpress inside public subnet 
resource "aws_instance" "nat_wpos" {
  count = var.instance_count

  ami                         = var.wordpress_ami
  instance_type               = var.instance_type
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.Natsub_public.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg_for_natwp.id]

  tags = {
    Name = "mywpos"
  }
}

# To launch instance for mysql inside private subnet
resource "aws_instance" "nat_sqlos" {
  count = var.instance_count

  ami                         = var.mysql_ami
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.Natsub_private.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg_for_natsql.id]

  tags = {
    Name = "mysqlos"
  }
}