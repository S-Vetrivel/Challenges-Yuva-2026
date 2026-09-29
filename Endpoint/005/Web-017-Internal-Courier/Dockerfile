FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js .
COPY entrypoint.sh .
COPY challenge.json .
COPY README.md .
COPY PLAYER_INFO.md .

RUN chmod +x entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/app/entrypoint.sh"]
