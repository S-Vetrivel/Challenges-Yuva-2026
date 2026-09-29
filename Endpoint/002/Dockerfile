FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --omit=dev

COPY server.js .
COPY frontend.html .
COPY entrypoint.sh .

RUN chmod +x entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/app/entrypoint.sh"]
