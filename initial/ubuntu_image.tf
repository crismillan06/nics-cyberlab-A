resource "openstack_images_image_v2" "ubuntu" {
  name             = "ubuntu-22.04"
  disk_format      = "qcow2"
  container_format = "bare"
  visibility       = "public"
  image_source_url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}
