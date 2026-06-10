FROM python:3.11-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash curl gnupg ca-certificates apt-transport-https \
    postgresql-client build-essential unixodbc unixodbc-dev \
  && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
  && apt-get update \
  && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/base/apps/source-db-importer

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
  && pip install --no-cache-dir -r /tmp/requirements.txt

CMD ["bash"]
