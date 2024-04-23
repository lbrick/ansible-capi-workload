# Ansible CAPI Workload role

## Note

You will need access to a CAPI management cluster to submit the following repo's code.

To bootstrap a CAPI management cluster please look at the following repo [NeSI RDC CAPI Management Cluster](https://github.com/nesi/nesi.rdc.kind-bootstrap-capi)

The CAPI images are generated from the following image bulder repo [CAPI Images](https://github.com/lbrick/image-builder/tree/2023-nesi_images)

## Using Cluster autoscaler

If the variable `cluster_max_worker_count` is greater then `cluster_worker_count` then Cluster Autoscaler will be deployed inside the workload cluster. This will not scale the GPU nodes if they are enabled at this stage.

## Using nodes with GPU access

If you have access to GPU flavor's within your RDC project space then you will need to set the variable `enable_gpu_nodes` to `true`

This will deploy a GPU node with the flavor `gpu1.44cpu240ram.a40.1g.48gb` and add it to the workload cluster

The following GPU CAPI images are avaliable:

``` { .sh }
Rocky 8.9

rocky-89-kube-nvidia-v1.27.7

```