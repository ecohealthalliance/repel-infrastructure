# script for the build before_script section of the gitlab-ci.yml file

echo $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY
echo $GIT_ENCRYPT_KEY64 > git_crypt_key.key64
base64 -d git_crypt_key.key64 > git_crypt_key.key
git-crypt unlock git_crypt_key.key
