## common
region = "ap-northeast-1"

key_name = "tjinjin-terraform"

project_name = "try-stretcher"

bastion_ami = "ami-ef545281"

## green settings
green_ami = "ami-ef545281"
green_instance_type = "t2.micro"

## blue settings
blue_ami    = "ami-ef545281"
blue_instance_type = "t2.micro"

## blue-green
blue_instances  = "0"
green_instances = "0"
