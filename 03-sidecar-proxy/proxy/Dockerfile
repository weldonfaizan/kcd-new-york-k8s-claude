FROM node:22-slim

WORKDIR /app

# Simple reverse proxy that injects credentials into outbound requests
COPY proxy.js /app/proxy.js

EXPOSE 8080

CMD ["node", "proxy.js"]
