#!/bin/bash

# NFS Subdir External Provisioner Installer
# This script installs a dynamic storage provisioner for existing NFS shares.

set -e

# --- Configuration ---
NFS_SERVER=${1:-"10.10.10.210"}
NFS_PATH=${2:-"/srv/nfs/kubedata"}
STORAGE_CLASS_NAME=${3:-"nfs-client"}

echo "🚀 Installing NFS Subdir External Provisioner..."
echo "📍 Server: $NFS_SERVER"
echo "📂 Path:   $NFS_PATH"
echo "🏷️  Class:  $STORAGE_CLASS_NAME"

# 1. Add Helm repo
echo "📦 Adding Helm repository..."
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# 2. Install via Helm
echo "🛠️  Running Helm install..."
helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server="$NFS_SERVER" \
  --set nfs.path="$NFS_PATH" \
  --set storageClass.name="$STORAGE_CLASS_NAME" \
  --set storageClass.defaultClass=false \
  --set replicaCount=1

echo "⏳ Waiting for provisioner to be ready..."
kubectl wait --for=condition=ready pod -l app=nfs-subdir-external-provisioner --timeout=120s

echo "✅ Success! StorageClass '$STORAGE_CLASS_NAME' is ready to use."
echo "📝 Usage: Set 'storageClassName: $STORAGE_CLASS_NAME' and 'accessModes: [ReadWriteMany]' in your PVCs."
