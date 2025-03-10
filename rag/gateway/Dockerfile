FROM node:18-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --only=production

COPY rag-gateway.js .
COPY .env .

EXPOSE 3100

CMD ["node", "rag-gateway.js"]
