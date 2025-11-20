#!/usr/bin/env bash
# ======================================================
# 🧹 Limpieza total de recursos en OpenStack
# Elimina: instancias, volúmenes, routers, redes, subredes,
# grupos de seguridad, imágenes y sabores.
# Autor: Younes Assouyat
# ======================================================

set -euo pipefail

echo "==============================================="
echo "⚠️  LIMPIEZA COMPLETA DE OPENSTACK"
echo "==============================================="
read -p "¿Seguro que deseas eliminar TODO (y/n)? " confirm
if [[ "$confirm" != "y" ]]; then
  echo "🚫 Operación cancelada."
  exit 0
fi

echo ""
echo "🧱 Eliminando instancias (servers)..."
for id in $(openstack server list -f value -c ID); do
  echo "🗑️ Eliminando instancia: $id"
  openstack server delete "$id" || true
done

echo ""
echo "💾 Eliminando volúmenes..."
for id in $(openstack volume list -f value -c ID); do
  echo "🗑️ Eliminando volumen: $id"
  openstack volume delete "$id" || true
done

echo ""
echo "🌐 Eliminando routers..."
for id in $(openstack router list -f value -c ID); do
  echo "🗑️ Eliminando router: $id"
  # Desconectar interfaces antes
  for port in $(openstack port list --router "$id" -f value -c ID); do
    echo "   🔌 Quitando interfaz del router $id → puerto $port"
    openstack router remove port "$id" "$port" || true
  done
  openstack router delete "$id" || true
done

echo ""
echo "📡 Eliminando subredes..."
for id in $(openstack subnet list -f value -c ID); do
  echo "🗑️ Eliminando subred: $id"
  openstack subnet delete "$id" || true
done

echo ""
echo "🌍 Eliminando redes..."
for id in $(openstack network list -f value -c ID); do
  echo "🗑️ Eliminando red: $id"
  openstack network delete "$id" || true
done

echo ""
echo "🔒 Eliminando grupos de seguridad..."
for id in $(openstack security group list -f value -c ID); do
  # Evitar eliminar el grupo "default" si no quieres perderlo:
  NAME=$(openstack security group show "$id" -f value -c name)
  if [[ "$NAME" == "default" ]]; then
    echo "⏭️  Saltando grupo default ($id)"
    continue
  fi
  echo "🗑️ Eliminando grupo de seguridad: $id ($NAME)"
  openstack security group delete "$id" || true
done

echo ""
echo "🖼️ Eliminando imágenes..."
for id in $(openstack image list -f value -c ID); do
  echo "🗑️ Eliminando imagen: $id"
  openstack image delete "$id" || true
done

echo ""
echo "⚙️ Eliminando sabores (flavors)..."
for id in $(openstack flavor list -f value -c ID); do
  echo "🗑️ Eliminando flavor: $id"
  openstack flavor delete "$id" || true
done

echo ""
echo "✅ Limpieza completada. Entorno OpenStack vacío."