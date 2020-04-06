import docker

# this script deletes all stops all running containers and
#   then deletes all containers, images and volumes from
#   you environment
# usage: python clean_all_docker.py

client = docker.from_env()

# stop all running containers
for container in client.containers.list():
    container.stop()

pruned_image_dict = client.images.prune(filters={'dangling': False})
pruned_container_dict = client.containers.prune()
pruned_volume_dict = client.volumes.prune()
