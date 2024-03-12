#!/bin/bash

#introspectionip=10.0.20.100:9090
[ -z "$introspectionip" ] && introspectionip=prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
#kubernetesip=10.0.20.100:6443
[ -n "$kubernetesip" ] && token=$(kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}")
[ -z "$kubernetesip" ] && kubernetesip=kubernetes.default.svc:443 && token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

allocatable_memory()
{
   allocatable_memory=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_allocatable_memory_bytes | jq '.data.result[0].value[1] | tonumber')
   echo $allocatable_memory | awk '{print $1/1024/1024/1024}'
}

allocatable_cpu()
{
   allocatable_cpu=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_allocatable_cpu_cores | jq '.data.result[0].value[1] | tonumber')
   echo $allocatable_cpu
}

allocatable_gpu()
{
   # https://www.urlencoder.org/
   # count(DCGM_FI_DEV_GPU_UTIL{gpu=~".*"}) = count%28DCGM_FI_DEV_GPU_UTIL%7Bgpu%3D~%22.%2A%22%7D%29
   #allocatable_gpu=$(curl -s http://$introspectionip/api/v1/query\?query\=count%28DCGM_FI_DEV_GPU_UTIL%29 | jq '.data.result[0].value[1] | tonumber')

   # curl https://$kubernetesip/api/v1/nodes --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
   # curl https://$kubernetesip/api --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
   
   # NVIDIA: nvidia.com/gpu
   # AMD: amd.com/gpu
   # INTEL: gpu.intel.com/i915

   #curl -s https://$kubernetesip/api/v1/nodes --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" | jq -r '.items[0].status.allocatable."nvidia.com/gpu"'
   allocatable_gpu=$(curl -sk https://$kubernetesip/api/v1/nodes --header "Authorization: Bearer $token" | jq -r '[.items[].status.allocatable | select( tostring | contains("gpu"))]' | awk -v s=0 -F '"' '/gpu/ {s+=$4} END {print s}')
   echo $allocatable_gpu
}

schedulable_memory()
{
   allocatable_memory=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_allocatable_memory_bytes | jq '.data.result[0].value[1] | tonumber')
   memory_usage=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_usage_memory_bytes | jq '.data.result[0].value[1] | tonumber')
   memory_requests=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_requests_memory_bytes | jq '.data.result[0].value[1] | tonumber')
   memory_limits=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_limits_memory_bytes | jq '.data.result[0].value[1] | tonumber')
   max_memory=$(printf '%d\n' $memory_usage $memory_requests $memory_limits | sort -nr | head -1)

   schedulable_memory=$((allocatable_memory-max_memory))
   echo $schedulable_memory | awk '{print $1/1024/1024/1024}'
}

schedulable_cpu()
{
   allocatable_cpu=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_allocatable_cpu_cores | jq '.data.result[0].value[1] | tonumber')
   cpu_usage=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_usage_cpu_cores | jq '.data.result[0].value[1] | tonumber')
   cpu_requests=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_requests_cpu_cores | jq '.data.result[0].value[1] | tonumber')
   cpu_limits=$(curl -s http://$introspectionip/api/v1/query\?query\=eagle_node_resource_limits_cpu_cores | jq '.data.result[0].value[1] | tonumber')
   max_cpu=$(printf '%f\n' $cpu_usage $cpu_requests $cpu_limits | sort -nr | head -1)

   schedulable_cpu=$(echo "$allocatable_cpu-$max_cpu" | bc)
   echo $schedulable_cpu
}

schedulable_gpu()
{
   allocatable_gpu=$(curl -sk https://$kubernetesip/api/v1/nodes --header "Authorization: Bearer $token" | jq -r '[.items[].status.allocatable | select( tostring | contains("gpu"))]' | awk -v s=0 -F '"' '/gpu/ {s+=$4} END {print s}')
   gpu_limits=$(curl -sk https://$kubernetesip/api/v1/pods?fieldSelector=spec.nodeName%3D5gmetamec%2Cstatus.phase%21%3DFailed%2Cstatus.phase%21%3DSucceeded --header "Authorization: Bearer $token" | jq -r '[.items[].spec.containers[].resources.limits | objects | select( tostring | contains("gpu"))]' | awk -v s=0 -F '"' '/gpu/ {s+=$4} END {print s}')
   
   schedulable_gpu=$(echo "$allocatable_gpu-$gpu_limits" | bc)
   echo $schedulable_gpu
}

help()
{
   echo "Program to get the allocatable and schedulable resources from a k8s node."
   echo
   echo "Syntax: introspection [-m|c|g|h]"
   echo "options:"
   echo "m:     Print the allocatable memory."
   echo "c:     Print the allocatable CPUs."
   echo "g:     Print the allocatable GPUs (if available)."
   echo "M:     Print the schedulable memory."
   echo "C:     Print the schedulable CPUs."
   echo "G:     Print the schedulable GPUs (if available)."
   echo "h:     Help."
}

[ $# -eq 0 ] && help
while getopts "mcgMCGh" option; do
   case $option in
      m) # Display allocatable memory
         allocatable_memory
         exit;;
      c) # Display allocatable cpu
         allocatable_cpu
         exit;;
      g) # Display allocatable gpu
         allocatable_gpu
         exit;;
      M) # Display schedulable memory
         schedulable_memory
         exit;;
      C) # Display schedulable cpu
         schedulable_cpu
         exit;;
      G) # Display schedulable gpu
         schedulable_gpu
         exit;;
      h | *) # Display help
         help
         exit;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done

#count(DCGM_FI_DEV_GPU_UTIL{gpu=~".*"})

#lshw -C video | awk -F'product: ' '/product/{print $2}'
#lshw -C video | awk -F'vendor: ' '/vendor/{print $2}'
#lspci -nn | grep VGA
#GPU=$(lspci | grep VGA | cut -d ":" -f3);RAM=$(cardid=$(lspci | grep VGA |cut -d " " -f1);lspci -s $cardid | grep " prefetchable"| cut -d "=" -f2);echo $GPU $RAM
#du -hs /var/lib/kubelet/* | sort -h -r
#docker system df
#curl -s http://$introspectionip/api/v1/query\?query\=kube_persistentvolume_capacity_bytes
#curl -s http://$introspectionip/api/v1/query\?query\=kube_persistentvolume_info
#nvidia-smi --list-gpus | wc -l