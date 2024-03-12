import sys
import subprocess
import requests
import yaml
import json
import uuid
#import re
#import connexion
#import six

from openapi_server.config.config import db
from openapi_server.models.instance import Instance, InstanceSchema  # noqa: E501
from openapi_server.models.instance_type import InstanceType#, InstanceTypeSchema # noqa: E501
# from openapi_server import util

from sqlalchemy.sql import func

def post_instance(payload):  # noqa: E501
    """Deploy a pipeline instance

     # noqa: E501

    :param body: 
    :type body: dict | bytes

    :rtype: Instance
    """
#    if connexion.request.is_json:
#        body = Instance.from_dict(connexion.request.get_json())  # noqa: E501

    if InstanceType.query.filter(InstanceType.type_name == payload["instance_type"]).one_or_none() is None:
        return "The selected instance type is not available on this Edge Server", 404

    try:
        #orchestrator_ip = subprocess.getoutput("if [ -z $orchestratorip ]; then kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}'; else echo $orchestratorip; fi")
        #orchestrator_ip = subprocess.check_output("if [ -z $introspectionip ]; then kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}'; else echo $introspectionip; fi", shell=True, text=True)
        orchestrator_ip = subprocess.getoutput("if [ -z $orchestratorip ]; then orchestratorip=nbi.osm.svc.cluster.local:9999 && echo $orchestratorip; else echo $orchestratorip; fi")
                    
        # Get authorization token
        url = 'https://' + orchestrator_ip + '/osm/admin/v1/tokens'
        headers = {"Content-Type": "application/json"}
        data = '{"username": "admin","password": "admin","project_id": "admin"}'
        response = requests.post(url, data=data, headers=headers, verify=False)
        yaml_response = yaml.safe_load(response.content)
        bearer = "Bearer " + yaml_response["id"]

        # Check if a specific pipeline for a datatype and instance type is already deployed
        url = 'https://' + orchestrator_ip + '/osm/nslcm/v1/ns_instances'
        headers = {'Authorization': bearer}
        response = requests.get(url, headers=headers, verify=False)
        orchestrator_response = yaml.safe_load(response.content)
        instance_index = next((index for (index, key) in enumerate(orchestrator_response) if key["name"] == payload["datatype"] + "-" + payload["instance_type"]), None)
        
        if instance_index is None: # There is no pipeline deployed for the selected datatype and instance type
            # Get the reserved resources from the database
            cpu_to_reserve = InstanceType.query.with_entities(InstanceType.cpu).filter(InstanceType.type_name == payload["instance_type"]).one()
            memory_to_reserve = InstanceType.query.with_entities(InstanceType.memory).filter(InstanceType.type_name == payload["instance_type"]).one()
            gpu = InstanceType.query.with_entities(InstanceType.gpu).filter(InstanceType.type_name == payload["instance_type"]).one()
            if gpu[0] == True:
                gpu_to_reserve = 1
            else:
                gpu_to_reserve = 0

            reserved_total_cpu = 0
            reserved_total_memory = 0
            reserved_total_gpu = 0

            deployed_datatypes = Instance.query.with_entities(Instance.datatype.distinct()).all()
            for deployed_datatype in deployed_datatypes:
                deployed_instance_types = Instance.query.with_entities(Instance.instance_type.distinct()).filter(Instance.datatype == deployed_datatype[0]).all()
                #deployed_instance_types = Instance.query.with_entities(Instance.instance_type.distinct()).all()
                
                for deployed_instance_type in deployed_instance_types:
                    #deployed_instance_type_number = Instance.query.filter(Instance.instance_type == deployed_instance_type[0]).count()
                    deployed_instance_type_number = 1
                    instance_type_cpu = InstanceType.query.with_entities(InstanceType.cpu).filter(InstanceType.type_name == deployed_instance_type[0]).one()
                    instance_type_memory = InstanceType.query.with_entities(InstanceType.memory).filter(InstanceType.type_name == deployed_instance_type[0]).one()
                    instance_type_gpu = InstanceType.query.with_entities(InstanceType.gpu).filter(InstanceType.type_name == deployed_instance_type[0]).one()
                    if instance_type_gpu[0] == True:
                        gpu_number = 1
                    else:
                        gpu_number = 0
                    reserved_total_cpu += deployed_instance_type_number * instance_type_cpu[0]
                    reserved_total_memory += deployed_instance_type_number * instance_type_memory[0]
                    reserved_total_gpu += deployed_instance_type_number * gpu_number

            # Get the allocatable and schedulable resources from the k8s node
            allocatable_cpu = float(subprocess.check_output(["./introspection.sh","-c"]))
            allocatable_memory = float(subprocess.check_output(["./introspection.sh","-m"]))
            allocatable_gpu = float(subprocess.check_output(["./introspection.sh","-g"]))
            schedulable_cpu = float(subprocess.check_output(["./introspection.sh","-C"]))
            schedulable_memory = float(subprocess.check_output(["./introspection.sh","-M"]))
            schedulable_gpu = float(subprocess.check_output(["./introspection.sh","-G"]))

            # Check if there is enough cpu and memory to make deploy the instance
            cpu_is_avaliable = False
            memory_is_avaliable = False
            gpu_is_avaliable = False
            if allocatable_cpu - reserved_total_cpu - cpu_to_reserve[0] >= 0 and schedulable_cpu - cpu_to_reserve[0] >= 0:
                cpu_is_avaliable = True
            if allocatable_memory - reserved_total_memory - memory_to_reserve[0] >= 0 and schedulable_memory - memory_to_reserve[0] >= 0:
                memory_is_avaliable = True
            if allocatable_gpu - reserved_total_gpu - gpu_to_reserve >= 0 and schedulable_gpu - gpu_to_reserve >= 0:
                gpu_is_avaliable = True

            print("     CPU_TO_RESERVE: " + str(cpu_to_reserve[0]), file=sys.stderr)
            print("     allocatable_cpu: " + str(allocatable_cpu), file=sys.stderr)
            print("     reserved_total_cpu: " + str(reserved_total_cpu), file=sys.stderr)
            print("     schedulable_cpu: " + str(schedulable_cpu), file=sys.stderr)
            print("     cpu_is_avaliable: " + str(cpu_is_avaliable), file=sys.stderr)
            print("     MEMORY_TO_RESERVE: " + str(memory_to_reserve[0]), file=sys.stderr)
            print("     allocatable_memory: " + str(allocatable_memory), file=sys.stderr)
            print("     reserved_total_memory: " + str(reserved_total_memory), file=sys.stderr)
            print("     schedulable_memory: " + str(schedulable_memory), file=sys.stderr)
            print("     memory_is_avaliable: " + str(memory_is_avaliable), file=sys.stderr)
            print("     GPU_TO_RESERVE: " + str(gpu_to_reserve), file=sys.stderr)
            print("     allocatable_gpu: " + str(allocatable_gpu), file=sys.stderr)
            print("     reserved_total_gpu: " + str(reserved_total_gpu), file=sys.stderr)
            print("     schedulable_gpu: " + str(schedulable_gpu), file=sys.stderr)
            print("     gpu_is_avaliable: " + str(gpu_is_avaliable), file=sys.stderr)

            if cpu_is_avaliable and memory_is_avaliable and gpu_is_avaliable:
                try:
                    # Deploy the pipeline
                        
                    # Get pipeline descriptor id
                    url = 'https://' + orchestrator_ip + '/osm/nsd/v1/ns_descriptors'
                    headers = {'Authorization': bearer}
                    response = requests.get(url, headers=headers, verify=False)
                    datatype_response = yaml.safe_load(response.content)
                    datatype_index = next((index for (index, key) in enumerate(datatype_response) if key["name"] == payload["datatype"]), None)
                    if datatype_index is None:
                        return "The selected datatype is not available on this Edge Server", 405

                    # Get vim id
                    url = 'https://' + orchestrator_ip + '/osm/admin/v1/vims/'
                    headers = {'Authorization': bearer}
                    response = requests.get(url, headers=headers, verify=False)
                    vim_response = yaml.safe_load(response.content)
                    vim_index = next((index for (index, key) in enumerate(vim_response) if key["name"] == "5gmeta-vim"), None)

                    # Pipeline Helm values:
                    #uid = str(uuid.uuid1())[:8]
                    enable_nv = "False" # Variable to enable GPU
                    if gpu_to_reserve == 1: enable_nv = "True"
                    values = {
                        "fullnameOverride":  payload["datatype"] + '-' + payload["instance_type"],
                        "resources": {
                            "limits": {
                                "cpu": str(cpu_to_reserve[0]),
                                "memory": str(memory_to_reserve[0]) + "Gi",
                                "nvidia.com/gpu": str(gpu_to_reserve)
                            },
                            "requests": {
                                "cpu": str(cpu_to_reserve[0]),
                                "memory": str(memory_to_reserve[0]) + "Gi"
                            }
                        },
                        "quota": {
                            "enabled": True,
                            "limits": {
                                "cpu": str(cpu_to_reserve[0]),
                                "memory": str(memory_to_reserve[0]) + "Gi"
                            },
                            "requests": {
                                "cpu": str(cpu_to_reserve[0]),
                                "memory": str(memory_to_reserve[0]) + "Gi",
                                "nvidia.com/gpu": str(gpu_to_reserve)
                            }
                        },
                        "osm_env": [
                            {
                                "name": "INSTANCE_TYPE",
                                "value": str(payload["instance_type"])
                            },
                            {
                                "name": "TOPIC_READ",
                                "value": str(payload["datatype"])
                            },
                            {
                                "name": "TOPIC_WRITE",
                                "value": str(payload["datatype"] + "-" + payload["instance_type"])
                            },
                            {
                                "name": "ENABLE_NV",
                                "value": enable_nv
                            }
                        ]
                    }

                    # Request to the orchestrator ip for deploying the pipeline
                    url = 'https://' + orchestrator_ip + '/osm/nslcm/v1/ns_instances_content'
                    headers = {'Content-Type': 'application/json', 'Authorization': bearer}
                    #data = '{ "nsName": "' + payload["username"] + '-' + payload["datatype"] + '", "nsdId": "' + datatype_response[datatype_index]["_id"] + '", "vimAccountId": "' + vim_response[vim_index]["_id"] + '", "additionalParamsForVnf": [ { "member-vnf-index": "1", "additionalParamsForKdu": [ { "kdu_name": "' + payload["datatype"] + '", "k8s-namespace": "' + payload["username"] + '", "additionalParams": { "fullnameOverride": "' + payload["datatype"] + '-' + str(uuid.uuid1())[:8] + '" } } ] } ] }'
                    #data = '{ "nsName": "' + re.sub('[\W_]+', '', payload["username"]) + '-' + payload["datatype"] + '-' + uid + '", "nsdId": "' + datatype_response[datatype_index]["_id"] + '", "vimAccountId": "' + vim_response[vim_index]["_id"] + '", "additionalParamsForVnf": [ { "member-vnf-index": "1", "additionalParamsForKdu": [ { "kdu_name": "' + payload["datatype"] + '", "k8s-namespace": "' + re.sub('[\W_]+', '', payload["username"]) + '-'  + payload["datatype"] + '-' + uid + '", "additionalParams": ' + json.dumps(values) + ' } ] } ] }'
                    data = '{ "nsName": "' + payload["datatype"] + '-' + payload["instance_type"] + '", "nsdId": "' + datatype_response[datatype_index]["_id"] + '", "vimAccountId": "' + vim_response[vim_index]["_id"] + '", "additionalParamsForVnf": [ { "member-vnf-index": "1", "additionalParamsForKdu": [ { "kdu_name": "' + payload["datatype"] + '", "k8s-namespace": "' + payload["datatype"] + '-' + payload["instance_type"] + '", "additionalParams": ' + json.dumps(values) + ' } ] } ] }'
                    print("     data: " + data, file=sys.stderr)
                    response = requests.post(url, data=data, headers=headers, verify=False)
                    orchestrator_response = yaml.safe_load(response.content)
                    instance_reference = orchestrator_response["id"]
                    print("     orchestrator_response: " + str(orchestrator_response), file=sys.stderr)
                except:
                    return "Error orchestrating the pipeline instance", 502
            else:
                return "There are no enough resources to deploy the instance", 501
        else:
            instance_reference = orchestrator_response[0]["id"]

        schema = InstanceSchema()

        # Use osm instance id as pipeline instance id
        payload["instance_reference"] = instance_reference
        payload["instance_id"] = str(uuid.uuid1())

        # Deserialize the received data
        new_instance = schema.load(payload)

        # Add the instance to the database
        db.session.add(new_instance)
        db.session.commit()

        # Serialize and return the newly created instance in the response
        data = schema.dump(new_instance)

        return data, 200
    except:
        return "Invalid instance", 400


def get_instances():  # noqa: E501
    """Get the deployed instances

    Get the deployed instances # noqa: E501


    :rtype: Instance
    """
    instances = Instance.query.all()

    instance_schema = InstanceSchema(many=True)

    data = instance_schema.dump(instances)

    return data, 200


def get_instance(instance_id):  # noqa: E501
    """Get a specific instance information

    Returns a single instance # noqa: E501

    :param instance_id: Specify the instance id to get the information
    :type instance_id: int

    :rtype: Instance
    """
    try:
        instance_schema = InstanceSchema()

        instance = Instance.query.filter(Instance.instance_id == instance_id).one()

        data = instance_schema.dump(instance)

        return data, 200
    except:
        return "Instance not found", 404


def delete_instance(instance_id):  # noqa: E501
    """Delete an instance

     # noqa: E501

    :param instance_id: Specify the instance id to delete the pipeline instance
    :type instance_id: int

    :rtype: Instance
    """
    try:
        instance_type = Instance.query.with_entities(Instance.instance_type).filter(Instance.instance_id == instance_id).one()
        datatype = Instance.query.with_entities(Instance.datatype).filter(Instance.instance_id == instance_id).one()
        pipeline_number = Instance.query.filter((Instance.instance_type == instance_type[0]) & (Instance.datatype == datatype[0])).count()

        if pipeline_number <= 1:
            try:
                instance_reference = Instance.query.with_entities(Instance.instance_reference).filter(Instance.instance_id == instance_id).one()
                orchestrator_ip = subprocess.getoutput("if [ -z $orchestratorip ]; then orchestratorip=nbi.osm.svc.cluster.local:9999 && echo $orchestratorip; else echo $orchestratorip; fi")

                # Get authorization token
                url = 'https://' + orchestrator_ip + '/osm/admin/v1/tokens'
                headers = {"Content-Type": "application/json"}
                data = '{"username": "admin","password": "admin","project_id": "admin"}'
                response = requests.post(url, data=data, headers=headers, verify=False)
                yaml_response = yaml.safe_load(response.content)
                bearer = "Bearer " + yaml_response["id"]

                # Delete the pipeline
                url = 'https://' + orchestrator_ip + '/osm/nslcm/v1/ns_instances/' + instance_reference[0] + '/terminate'
                headers = {'Content-Type': 'application/json', 'Authorization': bearer}
                data = '{"autoremove": true}'
                response = requests.post(url, data=data, headers=headers, verify=False)

                # # Get namespace name
                # url = 'https://' + orchestrator_ip + '/osm/nslcm/v1/ns_instances/' + instance_id
                # headers = {'Content-Type': 'application/json', 'Authorization': bearer}
                # response = requests.get(url, headers=headers, verify=False)
                # yaml_response = yaml.safe_load(response.content)
                # namespace = yaml_response["name"]

                # # Delete the namespace
                # subprocess.getstatusoutput("kubectl delete ns " + namespace)
            except:
                return 400

        instance = Instance.query.filter(Instance.instance_id == instance_id).one()

        db.session.delete(instance)

        db.session.commit()

        return "Instance successfully deleted", 200
    except:
        return "Instance not found", 404
