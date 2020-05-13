FROM node:7

COPY . /home/node/app
# ADD URL /home/node/app

WORKDIR /home/node/app

RUN npm install

EXPOSE 3000

CMD ["npm", "start"]
