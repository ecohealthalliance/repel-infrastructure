import docker
import boto3
import os
import tarfile

# this script pulls the current repel database backup from aws and installs
#   it in the currently running repel-infrastructure-postgres container.
# dependencies:
#   pip install boto3
# usage:
#   python pull_db_aws.py

# assuming script is being run from the scrapers directory
env_path = '../.env'

# read aws environment variables from .env
with open(env_path) as env_file:
    for line in env_file:
        if '=' not in line:
            continue
        if line.startswith('#'):
            continue
        if 'AWS' not in line:
            continue
        key, value = line.strip().split('=', 1)
        os.environ[key] = value

# download current backup file
bucket_name = 'repeldb'
file_name = 'dumps/repel_backup.dmp.xz'
s3 = boto3.resource('s3')
s3.Bucket(bucket_name).download_file(file_name, 'repel_backup.dmp.xz')

# make database update script
with open('update_database.sh', 'w') as script:
    script.write('#!/bin/bash\n')
    script.write('unxz repel_backup.dmp.xz\n')
    script.write('sudo -u postgres bash -c "dropdb \'repel\'"\n')
    script.write('sudo -u postgres bash -c "createdb \'repel\'"\n')
    script.write('sudo -u postgres bash -c "psql -d repel -f /repel_backup.dmp"\n')

# archive backup and script for transfer
with tarfile.open('repel_backup.tgz', 'w') as tar:
    tar.add('repel_backup.dmp.xz')
    tar.add('update_database.sh')

# find postgres container
target_container = ''
client = docker.from_env()
for container in client.containers.list():
    if 'postgres' in container.name:
        if target_container == '':
            target_container = container
        else:
            raise(ValueError('Found multiple postgres containers!'))

# transfer backup and script to postgres container
if target_container != '':
    data = open('repel_backup.tgz', 'rb').read()
    # copy archive to container
    target_container.put_archive('/', data)
    # run update database script in container
    target_container.exec_run('chmod +x /update_database.sh')
    target_container.exec_run('/update_database.sh')
else:
    raise(ValueError('No postgres container found!'))

# clean up temp files
os.system('rm repel_backup.*')
os.system('rm update_database.sh')
