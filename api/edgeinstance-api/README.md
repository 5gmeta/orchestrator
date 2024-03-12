## Overview
This API  uses the [Connexion](https://github.com/zalando/connexion) library on top of Flask.

## Requirements
Python 3.5.2+
MySQL database and the credentials for storing instances information
IP of the k8s cluster where the pipelines will be deployed

## Usage
To run the server, please execute the following commands from the root directory:

```
pip3 install -r requirements.txt
chmod +x introspection.sh
export db_host=<DB_HOST>
export db_root_password=<DB_ROOT_PASSWORD>
export db_name=<DB_NAME>
export introspectionip=<INTROSPECTION_IP> # Prometheus API IP and port
export kubernetesip=<KUBERNETES_IP> # Kubernetes API IP and port
export orchestratorip=<ORCHESTRATOR_IP> # OSM API IP and port
python3 -m openapi_server
```

and open your browser to here:

```
http://localhost:5000/ui/
```

Your OpenAPI definition lives here:

```
http://localhost:5000/openapi.json
```

## Running with Docker

To run the server on a Docker container, please execute the following from the root directory:

```bash
# building the image
docker build -t 5gmeta/edgeinstance-api .

# starting up a container
docker run -p 5000:5000 --env db_host=<DB_HOST> --env db_root_password=<DB_ROOT_PASSWORD> --env db_name=<DB_NAME> --env introspectionip=<NODE_IP> --env kubernetesip=<KUBERNETES_IP> --env orchestratorip=<ORCHESTRATOR_IP> 5gmeta/edgeinstance-api
```
