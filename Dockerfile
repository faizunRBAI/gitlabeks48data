FROM node:20-alpine
WORKDIR /app

# Install deps first so this layer is cached when only source changes.
COPY package*.json ./
# Use npm ci when package-lock.json is present (reproducible); fall back to
# npm install when it isn't (fresh scaffold without a committed lockfile).
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

# Copy app source.
COPY . .

# Run optional build step only when package.json defines one.
RUN if grep -q '"build"' package.json 2>/dev/null; then \
      if [ -f package-lock.json ]; then npm ci; else npm install; fi && \
      npm run build && \
      npm prune --omit=dev; \
    fi

EXPOSE 3000

# Start via the package.json "start" script so the scaffold controls the
# entry point (server.js for the UDAP Node scaffold, dist/main.js for Nest, etc).
CMD ["npm", "start"]
