FROM python:3.10-slim

# Install curl and kubectl for connectivity_probe.py which shells out to kubectl
RUN apt-get update && apt-get install -y curl && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/ && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Default command (will be overridden in deployment)
CMD ["python", "dns_probe.py"]

