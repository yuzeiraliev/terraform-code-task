output "public_dns" {
  value = aws_lb.web_alb.dns_name
}
