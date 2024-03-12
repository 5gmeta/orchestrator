#FROM python:3-alpine
FROM python:3.6-slim

RUN apt-get update && apt-get install -y curl jq bc

COPY requirements.txt .

RUN pip3 install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x introspection.sh

EXPOSE 5000

ENTRYPOINT ["python3"]

CMD ["-m", "openapi_server"]
