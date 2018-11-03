#!/bin/bash


# Add a route for the pod range
sudo ip route add 10.120.0.0/16 via 10.138.0.1


# Enable NAT for the shared network between GKE clusters.
sudo iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE


# Install Docker from the upstream binary release
wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.3.tgz
tar -xvf docker-1.12.3.tgz
sudo cp docker/docker* /usr/bin/

cat << 'EOF' > docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
ExecStart=/usr/bin/docker daemon \
  --iptables=false \
  --ip-masq=false \
  --host=unix:///var/run/docker.sock \
  --log-level=error \
  --storage-driver=overlay
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv docker.service /etc/systemd/system/docker.service

sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker


# Install the Kubernetes kubelet from the upstream binary release.
# The kubelet will run in standalone mode and will be used to run
# the nginx ingress controller pod.
wget https://storage.googleapis.com/kubernetes-release/release/v1.4.8/bin/linux/amd64/kubelet
chmod +x kubelet
sudo mv kubelet /usr/bin/

sudo mkdir -p /var/lib/kubelet/
sudo mkdir -p /etc/kubernetes/manifests

cat << 'EOF' > kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/kubelet \
  --allow-privileged=true \
  --cloud-provider= \
  --container-runtime=docker \
  --docker=unix:///var/run/docker.sock \
  --register-node=false \
  --pod-cidr=192.168.0.0/24 \
  --pod-manifest-path=/etc/kubernetes/manifests \
  --v=2

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kubelet.service /etc/systemd/system/kubelet.service

sudo systemctl daemon-reload
sudo systemctl enable kubelet
sudo systemctl start kubelet


# Download the cluster specific kubeconfig from the
# metadata service. Each kubeconfig should be build
# for each cluster.
curl -s -o kubeconfig -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/kubeconfig"

sudo mkdir -p /var/run/kubernetes/
sudo mv kubeconfig /var/run/kubernetes/kubeconfig


# Download the nginx ingress controller pod manifest from
# the metadata service and place it in the kubelet's pod
# manifest directory.
curl -s -o nginx-ingress-controller.yaml -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod"

sudo mv nginx-ingress-controller.yaml /etc/kubernetes/manifests/nginx-ingress-controller.yaml
