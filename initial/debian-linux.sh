#!/bin/bash

# Este script genera un archivo de Terraform para subir una imagen de Debian a OpenStack.

echo "=== Creando el fichero de Terraform: debian_image.tf ==="
cat <<EOF > debian_image.tf
resource "openstack_images_image_v2" "debian" {
  name             = "debian-12"
  disk_format      = "qcow2"
  container_format = "bare"
  visibility       = "public"
  image_source_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}
EOF

echo "=== Fichero 'debian_image.tf' creado con éxito. Ahora puedes ejecutar 'terraform init' y 'terraform apply' para subir la imagen. ==="
