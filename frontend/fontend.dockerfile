FROM node:16.20-buster-slim
RUN mkdir -p /home/node/app/node_modules && chown -R node:node /home/node/app
WORKDIR /home/node/app
COPY --chown=node:node package*.json ./
USER node
RUN npm install
COPY --chown=node:node . ./
ENV REACT_APP_API_URL ${REACT_APP_API_URL:-'http://localhost:8080/'}
EXPOSE 3000

CMD [ "npm", "start" ]