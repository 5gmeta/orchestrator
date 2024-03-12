#!/bin/bash

add_repo() {
  REPO_CHECK="^$1"
  grep "${REPO_CHECK/\[arch=amd64\]/\\[arch=amd64\\]}" /etc/apt/sources.list > /dev/null 2>&1
  if [ $? -ne 0 ]
  then
    need_packages_lw="software-properties-common apt-transport-https"
    echo -e "Checking required packages to add ETSI OSM debian repo: $need_packages_lw"
    dpkg -l $need_packages_lw &>/dev/null \
      || ! echo -e "One or several required packages are not installed. Updating apt cache requires root privileges." \
      || sudo apt-get -qy update \
      || ! echo "failed to run apt-get update" \
      || exit 1
    dpkg -l $need_packages_lw &>/dev/null \
      || ! echo -e "Installing $need_packages_lw requires root privileges." \
      || sudo apt-get install -y $need_packages_lw \
      || ! echo "failed to install $need_packages_lw" \
      || exit 1
    wget -qO - "$REPOSITORY_BASE/$RELEASE/OSM%20ETSI%20Release%20Key.gpg" | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE apt-key add -
    sudo DEBIAN_FRONTEND=noninteractive add-apt-repository -y "$1"
    sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 DEBIAN_FRONTEND=noninteractive apt-get -y update
    return 0
  fi

  return 1
}

clean_old_repo() {
dpkg -s 'osm-devops' &> /dev/null
if [ $? -eq 0 ]; then
  # Clean the previous repos that might exist
  sudo sed -i "/osm-download.etsi.org/d" /etc/apt/sources.list
fi
}

function install_lxd() {
     # Apply sysctl production values for optimal performance
    sudo cp ${OSM_DEVOPS}/installers/60-lxd-production.conf /etc/sysctl.d/60-lxd-production.conf
    sudo sysctl --system

    # Install LXD snap
    sudo apt-get remove --purge -y liblxc1 lxc-common lxcfs lxd lxd-client
    sudo snap install lxd --channel $LXD_VERSION/stable

    # Configure LXD
    sudo usermod -a -G lxd `whoami`
    cat ${OSM_DEVOPS}/installers/lxd-preseed.conf | sed 's/^config: {}/config:\n  core.https_address: '$DEFAULT_IP':8443/' | sg lxd -c "lxd init --preseed"
    sg lxd -c "lxd waitready"
    DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$DEFAULT_IF" ] && FATAL "Not possible to determine the interface with the default route 0.0.0.0"
    DEFAULT_MTU=$(ip addr show ${DEFAULT_IF} | perl -ne 'if (/mtu\s(\d+)/) {print $1;}')
    sg lxd -c "lxc profile device set default eth0 mtu $DEFAULT_MTU"
    sg lxd -c "lxc network set lxdbr0 bridge.mtu $DEFAULT_MTU"
    #sudo systemctl stop lxd-bridge
    #sudo systemctl --system daemon-reload
    #sudo systemctl enable lxd-bridge
    #sudo systemctl start lxd-bridge
}

function install_juju() {
    echo "Installing juju"
    sudo snap install juju --classic --channel=$JUJU_VERSION/stable
    [[ ":$PATH": != *":/snap/bin:"* ]] && PATH="/snap/bin:${PATH}"
    sleep 20
    update_juju_images
    echo "Finished installation of juju"
    return 0
}

function update_juju_images(){
    crontab -l | grep update-juju-lxc-images || (crontab -l 2>/dev/null; echo "0 4 * * 6 $USER ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic") | crontab -
    ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic
}

function parse_juju_password {
    password_file="${HOME}/.local/share/juju/accounts.yaml"
    local controller_name=$1
    local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $password_file |
    awk -F$fs -v controller=$controller_name '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            if (match(vn,controller) && match($2,"password")) {
                printf("%s",$3);
            }
        }
    }'
}

function juju_createcontroller_k8s(){
    cat $HOME/.kube/config | juju add-k8s $OSM_VCA_K8S_CLOUDNAME --client \
    || FATAL "Failed to add K8s endpoint and credential for client in cloud $OSM_VCA_K8S_CLOUDNAME"
    juju bootstrap -v --debug $OSM_VCA_K8S_CLOUDNAME $OSM_STACK_NAME  \
            --config controller-service-type=loadbalancer \
            --agent-version=$JUJU_AGENT_VERSION \
    || FATAL "Failed to bootstrap controller $OSM_STACK_NAME in cloud $OSM_VCA_K8S_CLOUDNAME"
}

function juju_addlxd_cloud(){
    mkdir -p /tmp/.osm
    OSM_VCA_CLOUDNAME="lxd-cloud"
    LXDENDPOINT=$DEFAULT_IP
    LXD_CLOUD=/tmp/.osm/lxd-cloud.yaml
    LXD_CREDENTIALS=/tmp/.osm/lxd-credentials.yaml

    cat << EOF > $LXD_CLOUD
clouds:
  $OSM_VCA_CLOUDNAME:
    type: lxd
    auth-types: [certificate]
    endpoint: "https://$LXDENDPOINT:8443"
    config:
      ssl-hostname-verification: false
EOF
    openssl req -nodes -new -x509 -keyout /tmp/.osm/client.key -out /tmp/.osm/client.crt -days 365 -subj "/C=FR/ST=Nice/L=Nice/O=ETSI/OU=OSM/CN=osm.etsi.org"
    cat << EOF > $LXD_CREDENTIALS
credentials:
  $OSM_VCA_CLOUDNAME:
    lxd-cloud:
      auth-type: certificate
      server-cert: /var/snap/lxd/common/lxd/server.crt
      client-cert: /tmp/.osm/client.crt
      client-key: /tmp/.osm/client.key
EOF
    lxc config trust add local: /tmp/.osm/client.crt
    juju add-cloud -c $OSM_STACK_NAME $OSM_VCA_CLOUDNAME $LXD_CLOUD --force
    juju add-credential -c $OSM_STACK_NAME $OSM_VCA_CLOUDNAME -f $LXD_CREDENTIALS
    sg lxd -c "lxd waitready"
    juju controller-config features=[k8s-operators]
}

function juju_createcontroller() {
    if ! juju show-controller $OSM_STACK_NAME &> /dev/null; then
        # Not found created, create the controller
        sudo usermod -a -G lxd ${USER}
        sg lxd -c "juju bootstrap --bootstrap-series=xenial --agent-version=$JUJU_AGENT_VERSION $OSM_VCA_CLOUDNAME $OSM_STACK_NAME"
    fi
    [ $(juju controllers | awk "/^${OSM_STACK_NAME}[\*| ]/{print $1}"|wc -l) -eq 1 ] || FATAL "Juju installation failed"
    juju controller-config features=[k8s-operators]
}

function juju_createproxy() {
    check_install_iptables_persistent

    if ! sudo iptables -t nat -C PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST; then
        sudo iptables -t nat -A PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST
        sudo netfilter-persistent save
    fi
}

function check_install_iptables_persistent(){
    echo -e "\nChecking required packages: iptables-persistent"
    if ! dpkg -l iptables-persistent &>/dev/null; then
        echo -e "    Not installed.\nInstalling iptables-persistent requires root privileges"
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
        sudo apt-get -yq install iptables-persistent
    fi
}

function set_vca_variables() {
    OSM_VCA_CLOUDNAME="lxd-cloud"

    OSM_VCA_HOST=`sg lxd -c "juju show-controller $OSM_STACK_NAME"|grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
    [ -z "$OSM_VCA_HOST" ] && FATAL "Cannot obtain juju controller IP address"

    OSM_VCA_SECRET=$(parse_juju_password $OSM_STACK_NAME)
    [ -z "$OSM_VCA_SECRET" ] && FATAL "Cannot obtain juju secret"

    OSM_VCA_PUBKEY=$(cat $HOME/.local/share/juju/ssh/juju_id_rsa.pub)
    [ -z "$OSM_VCA_PUBKEY" ] && FATAL "Cannot obtain juju public key"

    OSM_VCA_CACERT=$(juju controllers --format json | jq -r --arg controller $OSM_STACK_NAME '.controllers[$controller]["ca-cert"]' | base64 | tr -d \\n)
    [ -z "$OSM_VCA_CACERT" ] && FATAL "Cannot obtain juju CA certificate"
}

function check_for_readiness() {
    # Default input values
    sampling_period=2       # seconds
    time_for_readiness=20   # seconds ready
    time_for_failure=200    # seconds broken
    OPENEBS_NAMESPACE=openebs
    METALLB_NAMESPACE=metallb-system
    # STACK_NAME=osm          # By default, "osm"

    # Equivalent number of samples
    oks_threshold=$((time_for_readiness/${sampling_period}))     # No. ok samples to declare the system ready
    failures_threshold=$((time_for_failure/${sampling_period}))  # No. nok samples to declare the system broken
    failures_in_a_row=0
    oks_in_a_row=0

    ####################################################################################
    # Loop to check system readiness
    ####################################################################################
    while [[ (${failures_in_a_row} -lt ${failures_threshold}) && (${oks_in_a_row} -lt ${oks_threshold}) ]]
    do
        # State of OpenEBS
        OPENEBS_STATE=$(kubectl get pod -n ${OPENEBS_NAMESPACE} --no-headers 2>&1)
        OPENEBS_READY=$(echo "${OPENEBS_STATE}" | awk '$2=="1/1" || $2=="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
        OPENEBS_NOT_READY=$(echo "${OPENEBS_STATE}" | awk '$2!="1/1" && $2!="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
        COUNT_OPENEBS_READY=$(echo "${OPENEBS_READY}"| grep -v -e '^$' | wc -l)
        COUNT_OPENEBS_NOT_READY=$(echo "${OPENEBS_NOT_READY}" | grep -v -e '^$' | wc -l)

        # State of MetalLB
        METALLB_STATE=$(kubectl get pod -n ${METALLB_NAMESPACE} --no-headers 2>&1)
        METALLB_READY=$(echo "${METALLB_STATE}" | awk '$2=="1/1" || $2=="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
        METALLB_NOT_READY=$(echo "${METALLB_STATE}" | awk '$2!="1/1" && $2!="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
        COUNT_METALLB_READY=$(echo "${METALLB_READY}" | grep -v -e '^$' | wc -l)
        COUNT_METALLB_NOT_READY=$(echo "${METALLB_NOT_READY}" | grep -v -e '^$' | wc -l)

        # OK sample
        if [[ $((${COUNT_OPENEBS_NOT_READY}+${COUNT_METALLB_NOT_READY})) -eq 0 ]]
        then
            ((++oks_in_a_row))
            failures_in_a_row=0
            echo -ne ===\> Successful checks: "${oks_in_a_row}"/${oks_threshold}\\r
        # NOK sample
        else
            ((++failures_in_a_row))
            oks_in_a_row=0
            echo
            echo Bootstraping... "${failures_in_a_row}" checks of ${failures_threshold}

            # Reports failed pods in OpenEBS
            if [[ "${COUNT_OPENEBS_NOT_READY}" -ne 0 ]]
            then
                echo "OpenEBS: Waiting for ${COUNT_OPENEBS_NOT_READY} of $((${COUNT_OPENEBS_NOT_READY}+${COUNT_OPENEBS_READY})) pods to be ready:"
                echo "${OPENEBS_NOT_READY}"
                echo
            fi

            # Reports failed statefulsets
            if [[ "${COUNT_METALLB_NOT_READY}" -ne 0 ]]
            then
                echo "MetalLB: Waiting for ${COUNT_METALLB_NOT_READY} of $((${COUNT_METALLB_NOT_READY}+${COUNT_METALLB_READY})) pods to be ready:"
                echo "${METALLB_NOT_READY}"
                echo
            fi
        fi

        #------------ NEXT SAMPLE
        sleep ${sampling_period}
    done

    ####################################################################################
    # OUTCOME
    ####################################################################################
    if [[ (${failures_in_a_row} -ge ${failures_threshold}) ]]
    then
        echo
        FATAL "K8S CLUSTER IS BROKEN"
    else
        echo
        echo "K8S CLUSTER IS READY"
    fi
}

function generate_docker_images() {
    echo "Pulling docker images"

    sg docker -c "docker pull wurstmeister/zookeeper" || FATAL "cannot get zookeeper docker image"
    sg docker -c "docker pull wurstmeister/kafka:${KAFKA_TAG}" || FATAL "cannot get kafka docker image"
    sg docker -c "docker pull mongo" || FATAL "cannot get mongo docker image"
    sg docker -c "docker pull prom/prometheus:${PROMETHEUS_TAG}" || FATAL "cannot get prometheus docker image"
    sg docker -c "docker pull google/cadvisor:${PROMETHEUS_CADVISOR_TAG}" || FATAL "cannot get prometheus cadvisor docker image"
    sg docker -c "docker pull grafana/grafana:${GRAFANA_TAG}" || FATAL "cannot get grafana docker image"
    sg docker -c "docker pull mariadb:${KEYSTONEDB_TAG}" || FATAL "cannot get keystone-db docker image"
    sg docker -c "docker pull mysql:5" || FATAL "cannot get mysql docker image"

    echo "Pulling OSM docker images"
    for module in MON POL NBI KEYSTONE RO LCM NG-UI osmclient; do
        module_lower=${module,,}
        module_tag="${OSM_DOCKER_TAG}"

        echo "Pulling ${DOCKER_USER}/${module_lower}:${module_tag} docker image"
        sg docker -c "docker pull ${DOCKER_USER}/${module_lower}:${module_tag}" || FATAL "cannot pull $module docker image"
    done
    echo "Finished pulling and generating docker images"
}

function generate_k8s_manifest_files() {
    #kubernetes resources
    sudo cp -bR ${OSM_DEVOPS}/installers/docker/osm_pods $OSM_DOCKER_WORK_DIR
    sudo rm -f $OSM_K8S_WORK_DIR/mongo.yaml
#    sudo rm -f $OSM_K8S_WORK_DIR/light-ui.yaml
}

function generate_docker_env_files() {
    echo "Doing a backup of existing env files"
    sudo cp $OSM_DOCKER_WORK_DIR/keystone-db.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/keystone.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/lcm.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/mon.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/nbi.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/pol.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/ro-db.env{,~}
    sudo cp $OSM_DOCKER_WORK_DIR/ro.env{,~}

    echo "Generating docker env files"
    # LCM
    if [ ! -f $OSM_DOCKER_WORK_DIR/lcm.env ]; then
        echo "OSMLCM_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_HOST" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_HOST=${OSM_VCA_HOST}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_HOST.*|OSMLCM_VCA_HOST=$OSM_VCA_HOST|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_SECRET" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_SECRET=${OSM_VCA_SECRET}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_SECRET.*|OSMLCM_VCA_SECRET=$OSM_VCA_SECRET|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_PUBKEY" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_PUBKEY=${OSM_VCA_PUBKEY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_PUBKEY.*|OSMLCM_VCA_PUBKEY=${OSM_VCA_PUBKEY}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_CACERT" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_CACERT=${OSM_VCA_CACERT}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_CACERT.*|OSMLCM_VCA_CACERT=${OSM_VCA_CACERT}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if [ -n "$OSM_VCA_APIPROXY" ]; then
        if ! grep -Fq "OSMLCM_VCA_APIPROXY" $OSM_DOCKER_WORK_DIR/lcm.env; then
            echo "OSMLCM_VCA_APIPROXY=${OSM_VCA_APIPROXY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
        else
            sudo sed -i "s|OSMLCM_VCA_APIPROXY.*|OSMLCM_VCA_APIPROXY=${OSM_VCA_APIPROXY}|g" $OSM_DOCKER_WORK_DIR/lcm.env
        fi
    fi

    if ! grep -Fq "OSMLCM_VCA_ENABLEOSUPGRADE" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "# OSMLCM_VCA_ENABLEOSUPGRADE=false" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_APTMIRROR" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "# OSMLCM_VCA_APTMIRROR=http://archive.ubuntu.com/ubuntu/" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_CLOUD" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_CLOUD=${OSM_VCA_CLOUDNAME}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_CLOUD.*|OSMLCM_VCA_CLOUD=${OSM_VCA_CLOUDNAME}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_K8S_CLOUD" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_K8S_CLOUD=${OSM_VCA_K8S_CLOUDNAME}" | sudo tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        sudo sed -i "s|OSMLCM_VCA_K8S_CLOUD.*|OSMLCM_VCA_K8S_CLOUD=${OSM_VCA_K8S_CLOUDNAME}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    # RO
    MYSQL_ROOT_PASSWORD=$(generate_secret)
    if [ ! -f $OSM_DOCKER_WORK_DIR/ro-db.env ]; then
        echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" | sudo tee $OSM_DOCKER_WORK_DIR/ro-db.env
    fi
    if [ ! -f $OSM_DOCKER_WORK_DIR/ro.env ]; then
        echo "RO_DB_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" | sudo tee $OSM_DOCKER_WORK_DIR/ro.env
    fi
    if ! grep -Fq "OSMRO_DATABASE_COMMONKEY" $OSM_DOCKER_WORK_DIR/ro.env; then
        echo "OSMRO_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/ro.env
    fi

    # Keystone
    KEYSTONE_DB_PASSWORD=$(generate_secret)
    SERVICE_PASSWORD=$(generate_secret)
    if [ ! -f $OSM_DOCKER_WORK_DIR/keystone-db.env ]; then
        echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" | sudo tee $OSM_DOCKER_WORK_DIR/keystone-db.env
    fi
    if [ ! -f $OSM_DOCKER_WORK_DIR/keystone.env ]; then
        echo "ROOT_DB_PASSWORD=${MYSQL_ROOT_PASSWORD}" | sudo tee $OSM_DOCKER_WORK_DIR/keystone.env
        echo "KEYSTONE_DB_PASSWORD=${KEYSTONE_DB_PASSWORD}" | sudo tee -a $OSM_DOCKER_WORK_DIR/keystone.env
        echo "SERVICE_PASSWORD=${SERVICE_PASSWORD}" | sudo tee -a $OSM_DOCKER_WORK_DIR/keystone.env
    fi

    # NBI
    if [ ! -f $OSM_DOCKER_WORK_DIR/nbi.env ]; then
        echo "OSMNBI_AUTHENTICATION_SERVICE_PASSWORD=${SERVICE_PASSWORD}" | sudo tee $OSM_DOCKER_WORK_DIR/nbi.env
        echo "OSMNBI_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/nbi.env
    fi

    # MON
    if [ ! -f $OSM_DOCKER_WORK_DIR/mon.env ]; then
        echo "OSMMON_KEYSTONE_SERVICE_PASSWORD=${SERVICE_PASSWORD}" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
        echo "OSMMON_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
        echo "OSMMON_SQL_DATABASE_URI=mysql://root:${MYSQL_ROOT_PASSWORD}@mysql:3306/mon" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OS_NOTIFIER_URI" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OS_NOTIFIER_URI=http://${DEFAULT_IP}:8662" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        sudo sed -i "s|OS_NOTIFIER_URI.*|OS_NOTIFIER_URI=http://$DEFAULT_IP:8662|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_HOST" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_HOST=${OSM_VCA_HOST}" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        sudo sed -i "s|OSMMON_VCA_HOST.*|OSMMON_VCA_HOST=$OSM_VCA_HOST|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_SECRET" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_SECRET=${OSM_VCA_SECRET}" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        sudo sed -i "s|OSMMON_VCA_SECRET.*|OSMMON_VCA_SECRET=$OSM_VCA_SECRET|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_CACERT" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_CACERT=${OSM_VCA_CACERT}" | sudo tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        sudo sed -i "s|OSMMON_VCA_CACERT.*|OSMMON_VCA_CACERT=${OSM_VCA_CACERT}|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi


    # POL
    if [ ! -f $OSM_DOCKER_WORK_DIR/pol.env ]; then
        echo "OSMPOL_SQL_DATABASE_URI=mysql://root:${MYSQL_ROOT_PASSWORD}@mysql:3306/pol" | sudo tee -a $OSM_DOCKER_WORK_DIR/pol.env
    fi

    echo "Finished generation of docker env files"
}

#deploy charmed services
function deploy_charmed_services() {
    juju add-model $OSM_STACK_NAME $OSM_VCA_K8S_CLOUDNAME
    # The channel prefix is not always recognized (maybe it should be cs: not ch:
    # anyway by default it will get it from the Charm Store)
    # juju deploy ch:mongodb-k8s -m $OSM_STACK_NAME
    juju deploy mongodb-k8s -m $OSM_STACK_NAME
}

#creates secrets from env files which will be used by containers
function kube_secrets(){
    kubectl create ns $OSM_STACK_NAME
    kubectl create secret generic lcm-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/lcm.env
    kubectl create secret generic mon-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/mon.env
    kubectl create secret generic nbi-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/nbi.env
    kubectl create secret generic ro-db-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/ro-db.env
    kubectl create secret generic ro-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/ro.env
    kubectl create secret generic keystone-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/keystone.env
    kubectl create secret generic pol-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/pol.env
}

function update_manifest_files() {
    osm_services="nbi lcm ro pol mon ng-ui keystone prometheus"
    list_of_services=""
    for module in $osm_services; do
        module_upper="${module^^}"
        if ! echo $TO_REBUILD | grep -q $module_upper ; then
            list_of_services="$list_of_services $module"
        fi
    done
}

function namespace_vol() {
    osm_services="nbi lcm ro pol mon kafka mysql prometheus"
    for osm in $osm_services; do
        sudo  sed -i "s#path: /var/lib/osm#path: $OSM_NAMESPACE_VOL#g" $OSM_K8S_WORK_DIR/$osm.yaml
    done
}

#deploys osm pods and services
function deploy_osm_services() {
    sudo sed -i 's/nodePort: 3000/nodePort: 3001/' $OSM_K8S_WORK_DIR/grafana.yaml
    kubectl apply -n $OSM_STACK_NAME -f $OSM_K8S_WORK_DIR
}

function install_k8s_monitoring() {
    # install OSM monitoring
    sudo chmod +x $OSM_DEVOPS/installers/k8s/*.sh
    sudo $OSM_DEVOPS/installers/k8s/install_osm_k8s_monitoring.sh || FATAL_TRACK install_k8s_monitoring "k8s/install_osm_k8s_monitoring.sh failed"
}

function install_osmclient(){
    CLIENT_RELEASE=${RELEASE#"-R "}
    CLIENT_REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
    CLIENT_REPOSITORY=${REPOSITORY#"-r "}
    CLIENT_REPOSITORY_BASE=${REPOSITORY_BASE#"-u "}
    key_location=$CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE/$CLIENT_REPOSITORY_KEY
    curl $key_location | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add -
    sudo add-apt-repository -y "deb [arch=amd64] $CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE $CLIENT_REPOSITORY osmclient IM"
    sudo apt-get update
    sudo apt-get install -y python3-pip
    sudo -H LC_ALL=C python3 -m pip install -U pip
    sudo -H LC_ALL=C python3 -m pip install -U python-magic pyangbind verboselogs
    sudo apt-get install -y python3-osm-im python3-osmclient
    if [ -f /usr/lib/python3/dist-packages/osm_im/requirements.txt ]; then
        python3 -m pip install -r /usr/lib/python3/dist-packages/osm_im/requirements.txt
    fi
    if [ -f /usr/lib/python3/dist-packages/osmclient/requirements.txt ]; then
        sudo apt-get install -y libcurl4-openssl-dev libssl-dev
        python3 -m pip install -r /usr/lib/python3/dist-packages/osmclient/requirements.txt
    fi
    #sed 's,OSM_SOL005=[^$]*,OSM_SOL005=True,' -i ${HOME}/.bashrc
    #echo 'export OSM_HOSTNAME=localhost' >> ${HOME}/.bashrc
    #echo 'export OSM_SOL005=True' >> ${HOME}/.bashrc
    echo -e "\nOSM client installed"
    echo -e "OSM client assumes that OSM host is running in localhost (127.0.0.1)."
    echo -e "In case you want to interact with a different OSM host, you will have to configure this env variable in your .bashrc file:"
    echo "     export OSM_HOSTNAME=<OSM_host>"
    return 0
}

function add_local_k8scluster() {
    /usr/bin/osm --all-projects vim-create \
      --name _system-osm-vim \
      --account_type dummy \
      --auth_url http://dummy \
      --user osm --password osm --tenant osm \
      --description "dummy" \
      --config '{management_network_name: mgmt}'
    /usr/bin/osm --all-projects k8scluster-add \
      --creds ${HOME}/.kube/config \
      --vim _system-osm-vim \
      --k8s-nets '{"net1": null}' \
      --version '1.15' \
      --description "OSM Internal Cluster" \
      _system-osm-k8s
}

function generate_secret() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
}

function install_osm() {
    [ "$USER" == "root" ] && FATAL "You are running the installer as root. The installer is prepared to be executed as a normal user with sudo privileges."

    echo "Installing OSM"

    echo "Determining IP address of the interface with the default route"
    DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$DEFAULT_IF" ] && FATAL "Not possible to determine the interface with the default route 0.0.0.0"
    DEFAULT_IP=`ip -o -4 a s ${DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]}'`
    [ -z "$DEFAULT_IP" ] && FATAL "Not possible to determine the IP address of the interface with the default route"

    need_packages_lw="snapd"
    echo -e "Checking required packages: $need_packages_lw"
    dpkg -l $need_packages_lw &>/dev/null \
        || ! echo -e "One or several required packages are not installed. Updating apt cache requires root privileges." \
        || sudo apt-get update \
        || FATAL "failed to run apt-get update"
    dpkg -l $need_packages_lw &>/dev/null \
        || ! echo -e "Installing $need_packages_lw requires root privileges." \
        || sudo apt-get install -y $need_packages_lw \
        || FATAL "failed to install $need_packages_lw"
    install_lxd

    echo "Creating folders for installation"
    [ ! -d "$OSM_DOCKER_WORK_DIR" ] && sudo mkdir -p $OSM_DOCKER_WORK_DIR

    check_for_readiness
    install_juju
    juju_createcontroller_k8s
    juju_addlxd_cloud
    juju_createcontroller
    juju_createproxy
    set_vca_variables

    OSM_DATABASE_COMMONKEY=$(generate_secret)
    [ -z "OSM_DATABASE_COMMONKEY" ] && FATAL "Cannot generate common db secret"

    generate_docker_images
    generate_k8s_manifest_files
    generate_docker_env_files

    deploy_charmed_services
    kube_secrets
    update_manifest_files
    namespace_vol
    deploy_osm_services

    #install_k8s_monitoring

    install_osmclient

    echo -e "Checking OSM health state..."
    $OSM_DEVOPS/installers/osm_health.sh -s ${OSM_STACK_NAME} -k -f 8 || \
    echo -e "OSM is not healthy, but will probably converge to a healthy state soon." && \
    echo -e "Check OSM status with: kubectl -n ${OSM_STACK_NAME} get all" && \

    add_local_k8scluster

    wget -q -O- https://osm-download.etsi.org/ftp/osm-11.0-eleven/README2.txt &> /dev/null
    return 0
}

LXD_VERSION=4.0
JUJU_VERSION=2.9
JUJU_AGENT_VERSION=2.9.22
RELEASE="ReleaseELEVEN"
REPOSITORY="stable"
OSM_DEVOPS="/usr/share/osm-devops"
OSM_VCA_CLOUDNAME="localhost"
OSM_VCA_K8S_CLOUDNAME="k8scloud"
OSM_STACK_NAME=osm
REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/debian"
OSM_WORK_DIR="/etc/osm"
OSM_DOCKER_WORK_DIR="${OSM_WORK_DIR}/docker"
OSM_K8S_WORK_DIR="${OSM_DOCKER_WORK_DIR}/osm_pods"
OSM_HOST_VOL="/var/lib/osm"
OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_STACK_NAME}"
OSM_DOCKER_TAG=11
DOCKER_USER=opensourcemano
KAFKA_TAG=2.11-1.0.2
PROMETHEUS_TAG=v2.4.3
GRAFANA_TAG=latest
PROMETHEUS_NODE_EXPORTER_TAG=0.18.1
PROMETHEUS_CADVISOR_TAG=latest
KEYSTONEDB_TAG=10
#ELASTIC_VERSION=6.4.2
#ELASTIC_CURATOR_VERSION=5.5.4

#main
source $OSM_DEVOPS/common/all_funcs
clean_old_repo
add_repo "deb [arch=amd64] $REPOSITORY_BASE/$RELEASE $REPOSITORY devops"
sudo DEBIAN_FRONTEND=noninteractive apt-get -q update
sudo DEBIAN_FRONTEND=noninteractive apt-get install osm-devops

need_packages="git wget curl tar"

echo -e "Checking required packages: $need_packages"
dpkg -l $need_packages &>/dev/null \
  || ! echo -e "One or several required packages are not installed. Updating apt cache requires root privileges." \
  || sudo apt-get update \
  || FATAL "failed to run apt-get update"
dpkg -l $need_packages &>/dev/null \
  || ! echo -e "Installing $need_packages requires root privileges." \
  || sudo apt-get install -y $need_packages \
  || FATAL "failed to install $need_packages"
sudo snap install jq

[ "${OSM_STACK_NAME}" == "osm" ] || OSM_DOCKER_WORK_DIR="$OSM_WORK_DIR/stack/$OSM_STACK_NAME"
OSM_K8S_WORK_DIR="$OSM_DOCKER_WORK_DIR/osm_pods" && OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_STACK_NAME}"

#Installation starts here
wget -q -O- https://osm-download.etsi.org/ftp/osm-11.0-eleven/README.txt &> /dev/null

install_osm
touch ${HOME}/5gmeta/logs/osm11_installed
echo -e "\nDONE"
exit 0