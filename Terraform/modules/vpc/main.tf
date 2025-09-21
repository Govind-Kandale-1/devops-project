provider "aws" {
  region = "us-east-1"  # Adjust region as needed
}


# Create VPC
resource "aws_vpc" "test_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "custom-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.test_vpc.id

  tags = {
    Name = "custom-igw"
  }
}

# Create public subnets
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.test_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${var.availability_zones[count.index]}"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "private-subnet-${var.availability_zones[count.index]}"
  }
}

# Create database subnets
resource "aws_subnet" "db" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "db-subnet-${var.availability_zones[count.index]}"
  }
}

# Create Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count      = length(var.availability_zones)
  depends_on = [aws_internet_gateway.igw]
}

# Create NAT Gateways in each AZ (in public subnets)
resource "aws_nat_gateway" "nat" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "nat-gateway-${var.availability_zones[count.index]}"
  }
}

# Create route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate public route table to public subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Create route tables for private subnets
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name = "private-route-table-${var.availability_zones[count.index]}"
  }
}

# Associate private route tables to private subnets
resource "aws_route_table_association" "private_assoc" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Create route tables for DB subnets (no internet route)
resource "aws_route_table" "db" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.test_vpc.id

  tags = {
    Name = "db-route-table-${var.availability_zones[count.index]}"
  }
}

# Associate DB route tables to DB subnets
resource "aws_route_table_association" "db_assoc" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db[count.index].id
}



