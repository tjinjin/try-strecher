#resource "aws_nat_gateway" "demo" {
#    allocation_id = "${aws_eip.nat_gateway.id}"
#    subnet_id = "${aws_subnet.public.0.id}"
#}
#
#resource "aws_eip" "nat_gateway" {
#    vpc = true
#}

resource "aws_instance" "nat" {
    ami = "ami-03cf3903"              # amzn-ami-vpc-nat-hvm-2015.03.0.x86_64-gp2
    instance_type = "t2.micro"
    key_name = "${var.key_name}"
    security_groups = ["${aws_security_group.bastion.id}"]
    subnet_id = "${aws_subnet.public.0.id}"
    associate_public_ip_address = true
    source_dest_check = false
    iam_instance_profile = "${var.project_name}-instance"
    tags {
        Name = "demo-nat"
        Roles = "nat"
        Configuration = "terraform"
    }
}

resource "aws_elb" "common" {
    name = "common-load-balancer"
    subnets = ["${aws_subnet.public.*.id}"]
    security_groups = ["${aws_security_group.elb.id}"]
    cross_zone_load_balancing = true
    listener {
        instance_port = 8080
        instance_protocol = "http"
        lb_port = 8080
        lb_protocol = "http"
    }
    listener {
        instance_port = 8500
        instance_protocol = "http"
        lb_port = 8500
        lb_protocol = "http"
    }
    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 2
        timeout = 2
        target = "HTTP:8080/"
        interval = 5
    }
    tags {
        Name = "demo"
        Created = "terraform"
    }
}
