#!/bin/sh
# Genera group_vars/ci/vault.yml con contraseñas aleatorias, cifrado con Ansible Vault.
# El texto plano solo existe en /tmp del contenedor efímero; nunca se muestra ni se guarda en el repo.
# Uso (desde ansible/): .\ejecutar.ps1 sh /work/ansible/scripts/generar-vault-ci.sh
set -eu
destino=/work/ansible/group_vars/ci/vault.yml
if [ -f "$destino" ]; then echo "Ya existe $destino; no se sobrescribe."; exit 1; fi
umask 077
clave() { python3 -c 'import secrets; print(secrets.token_urlsafe(24))'; }
{
  echo "vault_sonar_db_password: $(clave)"
  echo "vault_sonar_admin_password: $(clave)"
  echo "vault_mariadb_ci_root_password: $(clave)"
  echo "vault_mariadb_ci_password: $(clave)"
} > /tmp/vault_ci.yml
ansible-vault encrypt /tmp/vault_ci.yml --output "$destino"
rm -f /tmp/vault_ci.yml
echo "Creado $destino (cifrado)."
