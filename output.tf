output "ec2_public_ip" {
  value = aws_instance.ubuntu_instance.public_ip
}
output "ubuntu-connect-string" {
  value = "ssh -o StrictHostKeyChecking=accept-new ubuntu@${aws_instance.ubuntu_instance.public_ip}"
}
