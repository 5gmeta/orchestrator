#!/usr/bin/env python3
from openapi_server.config.config import connexion_app

def main():
    connexion_app.add_api('edgeinstance.yaml', arguments={'title': 'Edge Instance API'}, pythonic_params=True)
    connexion_app.run(port=5000)

if __name__ == '__main__':
    main()
