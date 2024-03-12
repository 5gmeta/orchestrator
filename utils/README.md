# Signing Docker Images

All the image developers should sign every docker image or tag with the following guidelines.

Load the docker delegation private key ([5gmeta.key](https://github.com/5gmeta/orchestrator/blob/main/utils/5gmeta.key)) stored in this repository.
```
$ curl -s https://<id>@raw.githubusercontent.com/5gmetadmin/orchestrator/main/utils/5gmeta.key -o 5gmeta.key
$ sudo chmod 600 5gmeta.key
$ docker trust key load 5gmeta.key --name 5gmeta
```
Passphrase of the key:  ```<password>```

The loaded private key will be placed under
``` ~/.docker/trust/private ```

Push the image to DockerHub:
```
$ docker push 5gmeta/<image>:<tag>
```

Finally, sign the image with:
```
$ docker trust sign 5gmeta/<image>:<tag>
```
This command will sign the image and push the signature to Docker Hub.

The public key of 5gmeta delegations ([5gmeta.pub](https://github.com/5gmeta/orchestrator/blob/main/utils/5gmeta.pub)) is already added in the underlying Notary server of Docker Hub, allowing to sign images with the private key (loaded in the previous step) for the repos in the following list:
```
5gmeta/edgeinstance-api
5gmeta/cloudinstance-api
5gmeta/image-anonymizator
5gmeta/video-anonymizator
5gmeta/dashboard
5gmeta/dataflow-api
5gmeta/video-stream-broker
5gmeta/registration-api
5gmeta/message-converter
5gmeta/discovery-api
5gmeta/slaedge-api
5gmeta/slacloud-api
5gmeta/license-api
5gmeta/kafka-connect
5gmeta/gateway
5gmeta/message-broker
5gmeta/identity-api
5gmeta/helloworld
```
*If you want to sign any image that is not in the previous list, please contact the administrators.

## Inspecting signed images:
We can fetch info from Docker Hub (Notary in Docker registry) about the signatures and signatories status of the repo by:
```
$ docker trust inspect --pretty 5gmeta/<image>
```
This command shows which tags on this repository are signed as well as the list of people with signatures attached to this repository.

# Management of Docker Content Trust (FOR ADMINISTRATORS ONLY)
:warning: :no_entry: Please do not continue reading if you are not involved in the administration of DockerHub. :no_entry: :warning: 

As atated in the previous section the 5gmeta delegation public key has been already added to the Notary server of Docker Hub for every repository, using the root keys stored in the repository. The command used for doing this:
```
$ docker trust signer add --key 5gmeta.pub 5gmeta 5gmeta/<image>
```
The first time a delegation is added to a repository, the command will also initiate the repository using a local Notary canonical root key that has been already created ([root.key](https://github.com/5gmeta/orchestrator/blob/main/utils/root.key)). This includes creating the notary target (or repository) and snapshots keys, and rotating the snapshot key to be managed by the notary server. More information on these keys can be found [here](https://docs.docker.com/engine/security/trust/trust_key_mng/). To load and configure the passphrase of the root key:
```
$ docker trust key load root.key
$ export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE="<password>"
```
To add more delegations (public/private keys  to an already initialized repository the target or repository keys are needed. They have been compressed in the [tar.gz file](https://github.com/5gmeta/orchestrator/blob/main/utils/5gmeta_private_keys.tar.gz) of the repository. For adding them:
```
$ tar -xvf private_keys_backup.tar.gz -C /
```
The passphrase of these repository keys is the same as always. You can configure an env variable for usign it automatically:
```
$ export DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE="<password>"
```
The previous step is only needed as said for adding more delegations. If this is needed, after loading the target keys run the following commands:
```
$ docker trust key generate <delegation>
$ docker trust signer add --key <delegation.pub> <delegation> 5gmeta/<image>
```
The Docker client stores the keys in the `~/.docker/trust/private` directory. For backing them up:
```
$ umask 077; tar -zcvf private_keys_backup.tar.gz ~/.docker/trust/private; umask 022
```
For more information about Docker Content Trust (DCT): https://docs.docker.com/engine/security/trust/

## Connaisseur
What is Connaisseur?

A Kubernetes admission controller to integrate container image signature verification and trust pinning into a cluster. Connaisseur ensures integrity and provenance of container images in a Kubernetes cluster. To do so, it intercepts resource creation or update requests sent to the Kubernetes cluster, identifies all container images and verifies their signatures against pre-configured public keys. Based on the result, it either accepts or denies those requests.
To learn more about Connaisseur, visit the [full documentation](https://sse-secure-systems.github.io/connaisseur/).

### Helm values

Connaisseur is deployed using helm and configured via [helm values](https://github.com/5gmeta/orchestrator/blob/main/utils/connaisseur-values.yaml), so we will start there. We need to set Connaisseur to use the root public key, ([root.pub](https://github.com/5gmeta/orchestrator/blob/main/utils/root.pub)) that has been created in the previous section, for validation of the images. To do so, in the  `.validators`  section the  `5gmeta`  validator will be created, adding the public root key and DockerHub's credentials. For getting the public root key of any other repository you can check the following [tutorial](https://sse-secure-systems.github.io/connaisseur/v2.6.4/validators/notaryv1/#getting-the-public-root-key). After that, a new image policy `.policy` is created to apply the 5gmeta validator to the following pattern: `docker.io/5gmeta/*:*`. Finally namespaced validation is enabled, to allow ignoring validation in specific namespaces. We leave the rest untouched.
```
# configure Connaisseur deployment
deployment:
  replicasCount: 1
### VALIDATORS ###
# validators are a set of configurations (types, public keys, authentication)
# that can be used for validating one or multiple images (or image signatures).
# they are tied to their respective image(s) via the image policy below. there
# are a few handy validators pre-configured.
validators:
  # static validator that allows each image
  - name: allow
    type: static
    approve: true
  # static validator that denies each image
  - name: deny
    type: static
    approve: false
  # 5gmeta validator
  - name: 5gmeta
    type: notaryv1
    host: notary.docker.io
    trust_roots:
    - name: default
      key: |
        -----BEGIN PUBLIC KEY-----
        <XXXXX>
        -----END PUBLIC KEY-----
    auth:
      username: '<user>'
      password: '<password>'
  # the `default` validator is used if no validator is specified in image policy
  - name: default
    type: notaryv1  # or other supported validator (e.g. "cosign")
    host: notary.docker.io # configure the notary server for notaryv1 or rekor url for cosign
    trust_roots:
    # # the `default` key is used if no key is specified in image policy
    #- name: default
    #  key: |  # enter your public key below
    #    -----BEGIN PUBLIC KEY-----
    #    <add your public key here>
    #    -----END PUBLIC KEY-----
    #cert: |  # in case the trust data host is using a self-signed certificate
    #  -----BEGIN CERTIFICATE-----
    #  ...
    #  -----END CERTIFICATE-----
    #auth:  # credentials in case the trust data requires authentication
    #  # either (preferred solution)
    #  secret_name: mysecret  # reference a k8s secret in the form required by the validator type (check the docs)
    #  # or (only for notaryv1 validator)
    #  username: myuser
    #  password: mypass
  # pre-configured nv1 validator for public notary from Docker Hub
  - name: dockerhub-basics
    type: notaryv1
    host: notary.docker.io
    trust_roots:
      # public key for official docker images (https://hub.docker.com/search?q=&type=image&image_filter=official)
      # !if not needed feel free to remove the key!
      - name: docker-official
        key: |
          -----BEGIN PUBLIC KEY-----
          <XXXXXX>
          -----END PUBLIC KEY-----
      # public key securesystemsengineering repo including Connaisseur images
      # !this key is critical for Connaisseur!
      - name: securesystemsengineering-official
        key: |
          -----BEGIN PUBLIC KEY-----
          <XXXXXXXXX>
          -----END PUBLIC KEY-----

### IMAGE POLICY ###
# the image policy ties validators and images together whereby always only the most specific rule (pattern)
# is applied. specify if and how images should be validated by which validator via the validator name.
policy:
  - pattern: "*:*"
  - pattern: "docker.io/library/*:*"
    validator: dockerhub-basics
    with:
      trust_root: docker-official
  - pattern: "k8s.gcr.io/*:*"
    validator: allow
  - pattern: "docker.io/securesystemsengineering/*:*"
    validator: dockerhub-basics
    with:
      trust_root: securesystemsengineering-official
  - pattern: "docker.io/5gmeta/*:*"
    validator: 5gmeta

# in detection mode, deployment will not be denied, but only prompted
# and logged. this allows testing the functionality without
# interrupting operation.
detectionMode: false

# namespaced validation allows to restrict the namespaces that will be subject to Connaisseur verification.
# when enabled, based on namespaced validation mode ('ignore' or 'validate')
# - either all namespaces with label "securesystemsengineering.connaisseur/webhook=ignore" are ignored
# - or only namespaces with label "securesystemsengineering.connaisseur/webhook=validate" are validated.
# warning: enabling namespaced validation, allows roles with edit permission on a namespace to disable
# validation for that namespace
namespacedValidation:
  enabled: true
  mode: ignore  # 'ignore' or 'validate'
```
Connaisseur is automatically deployed and configured in a MEC server using the Ansible Playbook of this repository, but it could be deployed manually through:
```
$ helm repo add connaisseur https://sse-secure-systems.github.io/connaisseur/charts
$ helm install connaisseur connaisseur/connaisseur --atomic --create-namespace --namespace connaisseur -f connaisseur-values.yaml
```
## Authors
- Mikel Serón Esnal ([mseron@vicomtech.org](mailto:mseron@vicomtech.org), [GitHub](https://github.com/mikelseron))
