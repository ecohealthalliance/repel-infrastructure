FROM node:7

RUN apt-get update && apt-get install -y unzip vim

RUN mkdir -p /home/node/app

ADD https://github.com/ecohealthalliance/shiny-auth0/archive/master.zip /tmp

WORKDIR /tmp

RUN unzip master.zip

RUN cp -R /tmp/shiny-auth0-master/* /home/node/app

COPY .env /home/node/app

WORKDIR /home/node/app

COPY ./routes/index.js /home/node/app/routes/

RUN npm install

EXPOSE 3000

CMD ["npm", "start"]
