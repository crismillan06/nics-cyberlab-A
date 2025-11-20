#!/bin/bash

# Este script genera un archivo de Terraform para crear sabores en OpenStack.

echo "=== Creando el fichero de Terraform: flavors.tf ==="
cat <<EOF > flavors.tf
resource "openstack_compute_flavor_v2" "tiny" {
  name  = "tiny"
  vcpus = 1
  ram   = 512
  disk  = 5
}

resource "openstack_compute_flavor_v2" "small" {
  name  = "small"
  vcpus = 1
  ram   = 1024
  disk  = 10
}

resource "openstack_compute_flavor_v2" "medium" {
  name  = "medium"
  vcpus = 2
  ram   = 2048
  disk  = 20
}

resource "openstack_compute_flavor_v2" "large" {
  name  = "large"
  vcpus = 4
  ram   = 4096
  disk  = 40
}
EOF

echo "=== Fichero 'flavors.tf' creado con éxito. Ahora puedes ejecutar 'terraform init' y 'terraform apply' para crear los sabores. ==="
