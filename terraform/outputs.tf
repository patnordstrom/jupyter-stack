output "jupyter_lab_password" {
  value     = random_password.jupyter_lab_pass.result
  sensitive = true
}