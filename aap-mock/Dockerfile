FROM docker.io/library/node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
ENV PORT=8099
EXPOSE 8099
USER node
CMD ["node", "src/index.js"]
