# PostGIS database setup

From http://fuzzytolerance.info/blog/2018/12/04/Postgres-PostGIS-in-Docker-for-production/

# Container mechanics

**build**:  
docker-compose build

**bring up local workflow**:  
./start-local.sh 

OR

USERID=$(id -u) GROUPID=$(id -g) docker-compose -f docker-compose.yml -f docker-compose-local.yml up

**bring up production workflow**:  
docker-compose -f docker-compose.yml -f docker-compose-production.yml up

**bring down containers**:  
docker-compose down
