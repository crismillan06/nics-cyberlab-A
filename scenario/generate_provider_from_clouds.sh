#!/usr/bin/env bash
# bash generate_provider_from_clouds.sh [DIRECTORIO_DESTINO] 2>&1 | tee nombre_del_log.log
# ======================================================
# ⚙️ Generador automático de provider.tf para Kolla-OpenStack
# Compatible con la versión Python de yq
# Autor: Younes Assouyat
# ======================================================

set -e

KOLLA_CLOUDS="/etc/kolla/clouds.yaml"
TMP_JSON="/tmp/clouds.json"

# 📁 Directorio de salida (por defecto: actual)
OUTDIR="${1:-$(pwd)}"
OUTPUT_FILE="${OUTDIR}/provider.tf"

CLOUD_NAME="kolla-admin"

echo "==============================================="
echo "🧩 Generador de provider.tf para Kolla-OpenStack"
echo "==============================================="
echo "📂 Directorio destino: $OUTDIR"
echo "📄 Archivo de salida: $OUTPUT_FILE"
echo ""

# ------------------------------------------------------
# 🧱 1. Verificar dependencias
# ------------------------------------------------------
if ! command -v yq >/dev/null 2>&1; then
  echo "📦 Instalando yq (Python version)..."
  sudo apt update -y
  sudo apt install -y yq
else
  echo "✅ yq ya está instalado."
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "📦 Instalando Terraform..."
  sudo apt install -y curl gnupg lsb-release
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update -y && sudo apt install -y terraform
else
  echo "✅ Terraform ya está instalado."
fi

# ------------------------------------------------------
# 📘 2. Convertir /etc/kolla/clouds.yaml a JSON
# ------------------------------------------------------
if [ ! -f "$KOLLA_CLOUDS" ]; then
  echo "❌ No se encontró /etc/kolla/clouds.yaml"
  exit 1
fi

echo "✅ Encontrado /etc/kolla/clouds.yaml"
yq -r . "$KOLLA_CLOUDS" > "$TMP_JSON"

# ------------------------------------------------------
# ⚙️ 3. Extraer datos con jq
# ------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "📦 Instalando jq..."
  sudo apt install -y jq
fi

AUTH_URL=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.auth_url" "$TMP_JSON")
USERNAME=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.username" "$TMP_JSON")
PASSWORD=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.password" "$TMP_JSON")
PROJECT_NAME=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.project_name" "$TMP_JSON")
USER_DOMAIN=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.user_domain_name" "$TMP_JSON")
PROJECT_DOMAIN=$(jq -r ".clouds.\"$CLOUD_NAME\".auth.project_domain_name" "$TMP_JSON")
REGION_NAME=$(jq -r ".clouds.\"$CLOUD_NAME\".region_name" "$TMP_JSON")

if [ -z "$AUTH_URL" ] || [ "$AUTH_URL" = "null" ]; then
  echo "❌ Error: No se pudo leer la configuración del cloud '$CLOUD_NAME'."
  exit 1
fi

# ------------------------------------------------------
# 🧾 4. Generar provider.tf (en el directorio OUTDIR)
# ------------------------------------------------------
cat > "$OUTPUT_FILE" <<EOF
##############################################
# 🌐 Proveedor de OpenStack (Generado automáticamente)
# Fuente: $CLOUD_NAME desde /etc/kolla/clouds.yaml
# Autor: Younes Assouyat
##############################################

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.52.1"
    }
  }
  required_version = ">= 1.5.0"
}

provider "openstack" {
  auth_url    = "$AUTH_URL"
  tenant_name = "${PROJECT_NAME:-admin}"
  user_name   = "$USERNAME"
  password    = "$PASSWORD"
  domain_name = "${PROJECT_DOMAIN:-$USER_DOMAIN}"
  region      = "${REGION_NAME:-RegionOne}"
}
EOF

echo ""
echo "✅ provider.tf generado correctamente en:"
echo "   $OUTPUT_FILE"
echo ""
echo "📘 Puedes ejecutar ahora:"
echo "   cd $OUTDIR"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply -auto-approve -parallelism=4"
