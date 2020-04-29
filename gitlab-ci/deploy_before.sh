docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
echo $GIT_ENCRYPT_KEY64 > git_crypt_key.key64
base64 -d git_crypt_key.key64 > git_crypt_key.key
git-crypt unlock git_crypt_key.key
