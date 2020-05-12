FROM node:7

RUN mkdir -p /home/node/app/node_modules && chown -R node:node /home/node/app

working_dir: /home/node/app

USER node

RUN npm install

EXPOSE 3838

ENTRYPOINT []
CMD ["npm start"]
