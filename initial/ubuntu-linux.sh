#!/bin/bash

# Este script genera un archivo de Terraform para subir una imagen de Ubuntu a OpenStack.

echo "=== Creando el fichero de Terraform: ubuntu_image.tf ==="
cat <<EOF > ubuntu_image.tf
resource "openstack_images_image_v2" "ubuntu" {
  name             = "ubuntu-22.04"
  disk_format      = "qcow2"
  container_format = "bare"
  visibility       = "public"
  image_source_url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}
EOF

echo "=== Fichero 'ubuntu_image.tf' creado con éxito. Ahora puedes ejecutar 'terraform init' y 'terraform apply' para subir la imagen. ==="
