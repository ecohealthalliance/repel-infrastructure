FROM node:7

# COPY . /home/node/app
ADD https://github.com/ecohealthalliance/shiny-auth0/archive/master.zip /home/node/app

# WORKDIR /home/node/app

RUN npm install

EXPOSE 3000

CMD ["npm", "start"]
