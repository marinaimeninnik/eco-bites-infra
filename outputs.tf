output "instance_this_id" {
  description = "The id of the EC2 instance"
  value       = module.ec2_instance_webserver.instance_this_id
}
