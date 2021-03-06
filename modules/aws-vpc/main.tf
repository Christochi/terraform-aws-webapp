# fetches availability zones in the region
data "aws_availability_zones" "azs" {}

# create VPC
resource "aws_vpc" "my_vpc" {

  cidr_block = var.vpc-cidr # vpc supernet

  tags = {

    Name = "${var.tags.prefix}-vpc" # tochi-vpc

  }

}

# local variables for public and private network components
locals {

  # cidrsubnet() formulates the cidr block addresses
  public_cidr_list = [cidrsubnet(var.vpc-cidr, 8, 11),
  cidrsubnet(var.vpc-cidr, 8, 12), cidrsubnet(var.vpc-cidr, 8, 13)]

  private_cidr_list = [cidrsubnet(var.vpc-cidr, 8, 21),
  cidrsubnet(var.vpc-cidr, 8, 22), cidrsubnet(var.vpc-cidr, 8, 23)]

  # stores number of components to create
  public_instances  = var.pub-counter <= length(local.public_cidr_list) ? var.pub-counter : length(local.public_cidr_list)
  private_instances = var.priv-counter <= length(local.private_cidr_list) ? var.priv-counter : length(local.private_cidr_list)

}

# creates public subnet(s) in any azs
resource "aws_subnet" "public_subnet" {

  vpc_id = aws_vpc.my_vpc.id # vpc id

  # number of public subnet(s)
  count = local.public_instances

  # returns cibr block value per iteration
  cidr_block = local.public_cidr_list[count.index]

  # return az per iteration
  availability_zone = data.aws_availability_zones.azs.names[count.index]

  # assigned a public IP address to instances launched in the subnet
  map_public_ip_on_launch = true

  tags = {

    Name = "${var.tags.prefix}-public-subnet-${count.index + 1}"

  }

}

# creates private subnet(s) in 3 azs
resource "aws_subnet" "private_subnet" {

  vpc_id = aws_vpc.my_vpc.id # vpc id

  # number of private subnet(s)
  count = local.private_instances

  # returns cibr block value per iteration
  cidr_block = local.private_cidr_list[count.index]

  # return az per iteration
  availability_zone = data.aws_availability_zones.azs.names[count.index]

  tags = {

    Name = "${var.tags.prefix}-private-subnet-${count.index + 1}"

  }

}

# network internet gateway
resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.my_vpc.id # vpc id

  tags = {

    Name = "${var.tags.prefix}-igw"

  }
}

# elastic ip
resource "aws_eip" "eip" {

  vpc = true # the EIP is in a VPC

  tags = {

    Name = "${var.tags.prefix}-eip"

  }

}

# create NAT gateway in the public subnet(s)
resource "aws_nat_gateway" "nat" {

  allocation_id = aws_eip.eip.id # EIP allocation ID

  # count     = length(aws_subnet.public_subnet) # create NATs
  # subnet_id = aws_subnet.public_subnet[count.index].id
  subnet_id = aws_subnet.public_subnet[0].id

  tags = {

    Name = "${var.tags.prefix}-nat-${length(aws_subnet.public_subnet)}"

  }

}

# custom public route table
resource "aws_route_table" "public_route_table" {

  vpc_id = aws_vpc.my_vpc.id # vpc id

  route {

    cidr_block = var.cidr-route-table # traffic ip
    gateway_id = aws_internet_gateway.igw.id

  }

  tags = {

    Name = "${var.tags.prefix}-public-route-table"

  }
}

# associates public subnet(s) to route table
resource "aws_route_table_association" "public_route_table_assoc" {

  # number of instances to create
  count     = length(aws_subnet.public_subnet)
  subnet_id = aws_subnet.public_subnet[count.index].id

  route_table_id = aws_route_table.public_route_table.id

}

# custom private route table
resource "aws_route_table" "private_route_table" {

  vpc_id = aws_vpc.my_vpc.id # vpc id

  route {

    cidr_block     = var.cidr-route-table # traffic ip
    nat_gateway_id = aws_nat_gateway.nat.id

  }

  tags = {

    Name = "${var.tags.prefix}-private-route-table"

  }

}

# associates private subnet(s) to route table
resource "aws_route_table_association" "private_route_table_assoc" {

  count     = length(aws_subnet.private_subnet)
  subnet_id = aws_subnet.private_subnet[count.index].id

  route_table_id = aws_route_table.private_route_table.id

}

# fetches your ip addr
data "http" "myip" {

  url = "http://ipinfo.io/ip"

}

# create and attach security group to vpc
resource "aws_security_group" "sg" {

  name        = "${var.tags.prefix}-sg"
  description = "traffic rules"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    # fetches your ip address and 
    # removes newline characters at the end of a string
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"

    # ingress traffic ip
    cidr_blocks = [var.sg-inbound]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    # ingress traffic ip
    cidr_blocks = [var.sg-inbound]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    # egress traffic ip
    cidr_blocks = [var.sg-outbound]
  }

  tags = {

    Name = "${var.tags.prefix}-sg"

  }

}