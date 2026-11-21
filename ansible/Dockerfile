# Imagen para ejecutar Ansible desde Windows (Ansible no corre de forma nativa en Windows).
FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-client \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "ansible-core==2.21.6"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work/ansible
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["ansible", "--version"]
