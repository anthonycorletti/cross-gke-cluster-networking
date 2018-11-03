# Cross Kubernetes Networking with GKE

This tutorial attempts to document the steps necessary to expose Kubernetes services between two GKE clusters over internal IP addresses. 

## Overview

Each cluster will utilize the following components:

* c1 - GKE cluster running in us-west1-a
* c2 - GKE cluster running in us-west1-b
* c1-gw-1 - multi-nic VM running the nginx ingress controller. Serves as the service proxy and gateway for c1
* c1-gw-2 - multi-nic VM running the nginx ingress controller. Serves as the service proxy for c1
* c2-gw-1 - multi-nic VM running the nginx ingress controller. Serves as the service proxy and gateway for c2
* c2-gw-2 - multi-nic VM running the nginx ingress controller. Serves as the service proxy for c2
* c1-ilb - c1 internal load balancer (backends: c1-gw-1, c1-gw-2)
* c2-ilb - c2 internal load balancer (backends: c2-gw-1, c2-gw-2)

### Network Layout

* shared (10.210.200.0/24)
  * c1-gw-1
  * c1-gw-2
  * c2-gw-1
  * c2-gw-2
  * c1-ilb
  * c2-ilb
* cluster-1 (10.138.0.0/20)
  * c1
  * c1-gw-1
  * c1-gw-2
* cluster-2 (10.138.0.0/20)
  * c2
  * c2-gw-1
  * c2-gw-2

## Prerequisites

Internal load balancing is limited to a specific region. Networks can span zones, but not regions.

```
gcloud config set compute/region us-west1
```

### Create the networks

```
gcloud compute networks create shared --mode custom
```

```
gcloud compute networks subnets create services \
  --network shared \
  --region us-west1 \
  --range 10.210.200.0/24
```

```
gcloud compute networks create cluster-1
```

```
gcloud compute networks create cluster-2
```

```
for network in shared cluster-1 cluster-2; do
  gcloud compute firewall-rules create "${network}-allow-all" \
    --network $network \
    --allow all \
    --source-ranges 0.0.0.0/0
done
```

### Create GKE Clusters

```
gcloud container clusters create c1 \
  --cluster-ipv4-cidr 10.120.0.0/16 \
  --network cluster-1 \
  --zone us-west1-a
```

```
gcloud container clusters create c2 \
  --cluster-ipv4-cidr 10.120.0.0/16 \
  --network cluster-2 \
  --zone us-west1-b
```

### Create Gateway Instances 

Each gateway instances will provide NAT between each GKE cluster and run the nginx ingress controller to provide a service proxy over internal IP addresses.

#### c1 gateways (us-west1-a)

Before provisioning the gateway machines we need to gather the following:

* cluster credentials used to create a kubeconfig for each cluster. The kubeconfig is used by the nginx ingress controller to connect the GKE master and sync service information.

```
gcloud container clusters get-credentials c1 \
  --zone us-west1-a
```

```
C1_SERVER=$(gcloud container clusters describe c1 \
  --format 'value(endpoint)')
```

```
C1_CERTIFICATE_AUTHORITY_DATA=$(gcloud container clusters describe c1 \
  --format 'value(masterAuth.clusterCaCertificate)')
```

```
C1_CLIENT_CERTIFICATE_DATA=$(gcloud container clusters describe c1 \
  --format 'value(masterAuth.clientCertificate)')
```

```
C1_CLIENT_KEY_DATA=$(gcloud container clusters describe c1 \
  --format 'value(masterAuth.clientKey)')
```

```
kubectl config set-cluster gke --kubeconfig c1-kubeconfig
```

```
kubectl config set clusters.gke.server \
  "https://${C1_SERVER}" \
  --kubeconfig c1-kubeconfig
```

```
kubectl config set clusters.gke.certificate-authority-data \
  ${C1_CERTIFICATE_AUTHORITY_DATA} \
  --kubeconfig c1-kubeconfig
```

```
kubectl config set-credentials ingress-controller --kubeconfig c1-kubeconfig
```

```
kubectl config set users.ingress-controller.client-certificate-data \
  ${C1_CLIENT_CERTIFICATE_DATA} \
  --kubeconfig c1-kubeconfig
```

```
kubectl config set users.ingress-controller.client-key-data \
  ${C1_CLIENT_KEY_DATA} \
  --kubeconfig c1-kubeconfig
```

```
kubectl config set-context ingress-controller \
  --cluster=gke \
  --user=ingress-controller \
  --kubeconfig c1-kubeconfig
```

```
kubectl config use-context ingress-controller \
  --kubeconfig c1-kubeconfig
```

```
gcloud alpha compute instances create c1-gw-1 \
  --can-ip-forward \
  --image-family ubuntu-1604-lts \
  --image-project ubuntu-os-cloud \
  --metadata-from-file "startup-script=startup.sh","pod=nginx-ingress-controller.yaml","kubeconfig=c1-kubeconfig" \
  --network-interface "subnet=https://www.googleapis.com/compute/v1/projects/hightowerlabs/regions/us-west1/subnetworks/services" \
  --network-interface "subnet=cluster-1" \
  --zone us-west1-a
```

```
gcloud alpha compute instances create c1-gw-2 \
  --can-ip-forward \
  --image-family ubuntu-1604-lts \
  --image-project ubuntu-os-cloud \
  --metadata-from-file "startup-script=startup.sh","pod=nginx-ingress-controller.yaml","kubeconfig=c1-kubeconfig" \
  --network-interface "subnet=https://www.googleapis.com/compute/v1/projects/hightowerlabs/regions/us-west1/subnetworks/services" \
  --network-interface "subnet=cluster-1" \
  --zone us-west1-a
```

#### c2 gateways (us-west1-b)

```
gcloud container clusters get-credentials c2 \
  --zone us-west1-b
```

```
C2_SERVER=$(gcloud container clusters describe c2 \
  --zone us-west1-b \
  --format 'value(endpoint)')
```

```
C2_CERTIFICATE_AUTHORITY_DATA=$(gcloud container clusters describe c2 \
  --zone us-west1-b \
  --format 'value(masterAuth.clusterCaCertificate)')
```

```
C2_CLIENT_CERTIFICATE_DATA=$(gcloud container clusters describe c2 \
  --zone us-west1-b \
  --format 'value(masterAuth.clientCertificate)')
```

```
C2_CLIENT_KEY_DATA=$(gcloud container clusters describe c2 \
  --zone us-west1-b \
  --format 'value(masterAuth.clientKey)')
```

```
kubectl config set-cluster gke --kubeconfig c2-kubeconfig
```

```
kubectl config set clusters.gke.server \
  "https://${C2_SERVER}" \
  --kubeconfig c2-kubeconfig
```

```
kubectl config set clusters.gke.certificate-authority-data \
  ${C2_CERTIFICATE_AUTHORITY_DATA} \
  --kubeconfig c2-kubeconfig
```

```
kubectl config set-credentials ingress-controller --kubeconfig c2-kubeconfig
```

```
kubectl config set users.ingress-controller.client-certificate-data \
  ${C2_CLIENT_CERTIFICATE_DATA} \
  --kubeconfig c2-kubeconfig
```

```
kubectl config set users.ingress-controller.client-key-data \
  ${C2_CLIENT_KEY_DATA} \
  --kubeconfig c2-kubeconfig
```

```
kubectl config set-context ingress-controller \
  --cluster=gke \
  --user=ingress-controller \
  --kubeconfig c2-kubeconfig
```

```
kubectl config use-context ingress-controller \
  --kubeconfig c2-kubeconfig
```



```
gcloud alpha compute instances create c2-gw-1 \
 --can-ip-forward \
 --image-family ubuntu-1604-lts \
 --image-project ubuntu-os-cloud  \
 --metadata-from-file "startup-script=startup.sh","pod=nginx-ingress-controller.yaml","kubeconfig=c2-kubeconfig" \
 --network-interface "subnet=https://www.googleapis.com/compute/v1/projects/hightowerlabs/regions/us-west1/subnetworks/services" \
 --network-interface "subnet=cluster-2" \
 --zone us-west1-b
```

```
gcloud alpha compute instances create c2-gw-2 \
 --can-ip-forward \
 --image-family ubuntu-1604-lts \
 --image-project ubuntu-os-cloud  \
 --metadata-from-file "startup-script=startup.sh","pod=nginx-ingress-controller.yaml","kubeconfig=c2-kubeconfig" \
 --network-interface "subnet=https://www.googleapis.com/compute/v1/projects/hightowerlabs/regions/us-west1/subnetworks/services" \
 --network-interface "subnet=cluster-2" \
 --zone us-west1-b
```

### Create Instance Groups

```
gcloud compute instance-groups unmanaged create c1-gw-instance-group \
  --zone us-west1-a
```

```
gcloud compute instance-groups unmanaged add-instances c1-gw-instance-group \
  --instances c1-gw-1,c1-gw-2 \
  --zone us-west1-a
```

```
gcloud compute instance-groups unmanaged create c2-gw-instance-group \
  --zone us-west1-b
```

```
gcloud compute instance-groups unmanaged add-instances c2-gw-instance-group \
  --instances c2-gw-1,c2-gw-2 \
  --zone us-west1-b
```

### Create Internal Load Balancer

```
gcloud compute health-checks create tcp ingress-controller-health-check --port 80
```

```
gcloud compute backend-services create c1-backend-services \
  --health-checks ingress-controller-health-check \
  --load-balancing-scheme internal \
  --region us-west1
```

```
gcloud compute backend-services add-backend c1-backend-services \
  --instance-group c1-gw-instance-group \
  --instance-group-zone us-west1-a \
  --region us-west1
```

```
gcloud compute forwarding-rules create c1-forwarding-rules \
  --backend-service c1-backend-services \
  --load-balancing-scheme internal \
  --network shared \
  --ports 80 \
  --region us-west1 \
  --subnet services
```

#### c2

```
gcloud compute backend-services create c2-backend-services \
  --health-checks ingress-controller-health-check \
  --load-balancing-scheme internal \
  --region us-west1
```

```
gcloud compute backend-services add-backend c2-backend-services \
  --instance-group c2-gw-instance-group \
  --instance-group-zone us-west1-b \
  --region us-west1
```

```
gcloud compute forwarding-rules create c2-forwarding-rules \
  --backend-service c2-backend-services \
  --load-balancing-scheme internal \
  --network shared \
  --ports 80 \
  --region us-west1 \
  --subnet services
```

### Add routes

```
gcloud compute routes create c1-service-route \
  --network cluster-1 \
  --next-hop-instance c1-gw-1 \
  --next-hop-instance-zone us-west1-a \
  --destination-range 10.210.200.0/24
```

```
gcloud compute routes create c2-service-route \
  --network cluster-2 \
  --next-hop-instance c2-gw-1 \
  --next-hop-instance-zone us-west1-b \
  --destination-range 10.210.200.0/24
```

### Kubernetes

In this section we need to install an example service in each cluster so we can
test the ability to communication between clusters.

Fetch the credentials for `c1`:

```
gcloud container clusters get-credentials c1 \
  --zone us-west1-a
```

Create the echoserver deployment:

```
kubectl run echoheaders \
  --image=gcr.io/google_containers/echoserver:1.4 \
  --replicas=1 \
  --port=8080
```

Expose the echoserver using a service. This is required before creating an ingress
config:

```
kubectl expose deployment echoheaders --port=80 --target-port=8080 --name=echoheaders-x
```
```
kubectl expose deployment echoheaders --port=80 --target-port=8080 --name=echoheaders-y
```

Create the ingress controller config. This will cause the nginx ingress controller running on
the gateway machines to pick up the echoserver backends and start routing HTTP requests to them.

```
kubectl create -f echomap-ingress.yaml
```

### Testing the nginx ingress controller

```
gcloud compute ssh c1-gw-1
```

```
curl -H "Host: foo.bar.com" http://127.0.0.1/foo
```

```
CLIENT VALUES:
client_address=10.138.0.5
command=GET
real path=/foo
query=nil
request_version=1.1
request_uri=http://foo.bar.com:8080/foo

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
connection=close
host=foo.bar.com
user-agent=curl/7.50.1
x-forwarded-for=127.0.0.1
x-forwarded-host=foo.bar.com
x-forwarded-port=80
x-forwarded-proto=http
x-real-ip=127.0.0.1
BODY:
-no body in request-
```

Test using the internal IP address:

```
curl -H "Host: foo.bar.com" http://c1-gw-1/foo
```


#### Testing from a pod

```
kubectl run --tty -i ubuntu --image=ubuntu /bin/bash
```

Once on the pod, install curl and hit the `c1-gw-1` service gateway:

```
apt-get update
```

```
apt-get install curl
```

Hit the `c1-gw-1` gateway from the pod:

> 10.210.200.2 is the internal IP address of c1-gw-1 on the shared network

```
curl -H "Host: foo.bar.com" http://10.210.200.2/foo
```

```
CLIENT VALUES:
client_address=10.138.0.5
command=GET
real path=/foo
query=nil
request_version=1.1
request_uri=http://foo.bar.com:8080/foo

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
connection=close
host=foo.bar.com
user-agent=curl/7.47.0
x-forwarded-for=10.120.1.4
x-forwarded-host=foo.bar.com
x-forwarded-port=80
x-forwarded-proto=http
x-real-ip=10.120.1.4
BODY:
-no body in request-
```

Hit the c1 internal load balancer (c1-forwarding-rules) from the pod:

> 10.210.200.6 is the IP address assigned to the ILB

```
curl -H "Host: foo.bar.com" http://10.210.200.6/foo
```
```
CLIENT VALUES:
client_address=10.138.0.5
command=GET
real path=/foo
query=nil
request_version=1.1
request_uri=http://foo.bar.com:8080/foo

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
connection=close
host=foo.bar.com
user-agent=curl/7.47.0
x-forwarded-for=10.120.1.4
x-forwarded-host=foo.bar.com
x-forwarded-port=80
x-forwarded-proto=http
x-real-ip=10.120.1.4
BODY:
-no body in request-
```

## Testing Cross Cluster Communication

This is where I could not get things to work. The following flow does not seem to work as expected. I think there is something wrong with the gateway to gateway communication over the shared network.

```
pod (c1) <-> c1-gw-1 <-> c2-gw-1 <-> pod (c2)
```

This flow also does not work:

```
pod (c1) <-> c2 ILB (c2-forwarding-rules)
```

What's odd is that communication between c1-gw-1 and c2-gw-1 works, but not pod (c1) and pod (c2).

### Reproduce the issue

Set up the echoserver on c2:

```
gcloud container clusters get-credentials c2 \
  --zone us-west1-b
```

```
kubectl run echoheaders \
  --image=gcr.io/google_containers/echoserver:1.4 \
  --replicas=1 \
  --port=8080
```

```
kubectl expose deployment echoheaders --port=80 --target-port=8080 --name=echoheaders-x
```

```
kubectl expose deployment echoheaders --port=80 --target-port=8080 --name=echoheaders-y
```

```
kubectl create -f echomap-ingress.yaml
```

### Test between c1-gw-1 and c2-gw-1

```
gcloud compute ssh c1-gw-1
```

```
curl -H "Host: foo.bar.com" http://c2-gw-1/foo
```
```
CLIENT VALUES:
client_address=10.138.0.5
command=GET
real path=/foo
query=nil
request_version=1.1
request_uri=http://foo.bar.com:8080/foo

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
connection=close
host=foo.bar.com
user-agent=curl/7.50.1
x-forwarded-for=10.210.200.2
x-forwarded-host=foo.bar.com
x-forwarded-port=80
x-forwarded-proto=http
x-real-ip=10.210.200.2
BODY:
-no body in request-
```

### Test between pod (c1) <-> c2-gw-1

```
gcloud container clusters get-credentials c1 \
  --zone us-west1-a
```

```
kubectl run --tty -i ubuntu --image=ubuntu /bin/bash
```
> or just use the ubuntu pod from earlier

```
curl -H "Host: foo.bar.com" http://10.210.200.7/foo
```

> 10.210.200.7 is the IP address assigned to the ILB (c2-forwarding-rules)
