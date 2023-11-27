locals {
  name = var.name == null ? "sudo-${random_string.random_name[0].result}" : var.name
}

resource "random_string" "random_name" {
  count   = var.name == null ? 1 : 0
  length  = 8
  special = false
  upper   = false
}
