FROM node:7

RUN apt-get update && apt-get install -y unzip

RUN mkdir -p /home/node/app

# COPY . /home/node/app
ADD https://github.com/ecohealthalliance/shiny-auth0/archive/master.zip /home/node

RUN unzip /home/node/master.zip

RUN mv shiny-auth0-master app

WORKDIR /home/node/app

RUN npm install

EXPOSE 3000

CMD ["npm", "start"]
