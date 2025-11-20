#!/bin/bash
set -e

# Este script descarga la imagen más reciente de Kali Linux,
# la descomprime y la sube a OpenStack usando la CLI.

# URL de la imagen de Kali 2025.2 comprimida
IMAGE_URL="https://kali.download/cloud-images/kali-2025.2/kali-linux-2025.2-cloud-genericcloud-amd64.tar.xz"
# Nombre del archivo comprimido
COMPRESSED_FILE="kali-linux-2025.2-cloud-genericcloud-amd64.tar.xz"
# Nombre del archivo de imagen descomprimido
UNCOMPRESSED_FILE="kali-disk.raw"
# Nombre que tendrá la imagen en OpenStack
IMAGE_NAME="kali-linux-2025.2"

echo "=== 1. Descargando la imagen de Kali Linux 2025.2 ==="
curl -O "$IMAGE_URL"

echo "=== 2. Descomprimiendo el archivo de imagen ==="
tar -xf "$COMPRESSED_FILE"

# Renombra el archivo disk.raw a kali-disk.raw
echo "=== Renombrando disk.raw a kali-disk.raw ==="
mv "disk.raw" "$UNCOMPRESSED_FILE"

# Genera el archivo de Terraform después de la descompresión
echo "=== 3. Creando el fichero de Terraform: kali-linux.tf ==="
cat <<EOF > kali_image.tf
resource "openstack_images_image_v2" "kali_linux" {
  name             = "${IMAGE_NAME}"
  disk_format      = "qcow2"
  container_format = "bare"
  visibility       = "public"
  image_source_url = file("${UNCOMPRESSED_FILE}")
}
EOF

echo "=== Proceso completado. Fichero 'kali-linux.tf' creado con éxito. ==="
