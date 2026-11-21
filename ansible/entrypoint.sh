#!/bin/sh
# Los volúmenes montados desde Windows llegan con permisos 777 y ssh rechaza llaves "desprotegidas".
# Se copia la llave a un archivo propio con permisos 600 antes de ejecutar Ansible.
set -e
if [ -f /llaves/id_gestor ]; then
  mkdir -p /root/.ssh
  cp /llaves/id_gestor /root/.ssh/id_gestor
  chmod 600 /root/.ssh/id_gestor
fi
if [ -f /secretos/vault_pass ]; then
  cp /secretos/vault_pass /root/.vault_pass
  chmod 600 /root/.vault_pass
fi
exec "$@"
