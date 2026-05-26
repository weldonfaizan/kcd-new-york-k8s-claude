FROM python:3.13-slim

# kubernetes v36 has a regression where Bearer tokens aren't sent (github.com/kubernetes-client/python/issues/2582)
RUN pip install --no-cache-dir "k8s-agent-sandbox==0.4.6" "kubernetes>=31,<32"

WORKDIR /app
COPY dispatch.py /app/dispatch.py

ENTRYPOINT ["python3", "/app/dispatch.py"]
