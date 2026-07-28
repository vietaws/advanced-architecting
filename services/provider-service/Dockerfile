FROM node:24-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN mkdir -p /data/efs

EXPOSE 3002
CMD ["node", "server.js"]
