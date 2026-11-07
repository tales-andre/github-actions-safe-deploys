# syntax=docker/dockerfile:1

# Base: distroless Node.js 22 (no shell, no package manager). The tag is rebuilt upstream
# when Debian ships security fixes, and every build is scanned by Trivy in build.yml.
# For bit-for-bit reproducible builds, pin the digest instead and let Dependabot bump it.
ARG BASE_IMAGE=gcr.io/distroless/nodejs22-debian13:nonroot

# Stage 1: run the unit tests on the same Node.js that ships. If a test fails, no image exists.
FROM ${BASE_IMAGE} AS test
WORKDIR /app
COPY package.json ./
COPY src ./src
COPY test ./test
RUN ["/nodejs/bin/node", "--test"]

# Stage 2: the runtime image, with the source only (no tests, no dev files).
FROM ${BASE_IMAGE}
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.title="kettlebird-hello" \
      org.opencontainers.image.description="Minimal HTTP service for the github-actions-safe-deploys demo" \
      org.opencontainers.image.licenses="MIT"
WORKDIR /app
COPY --from=test /app/package.json ./
COPY --from=test /app/src ./src
# Numeric UID so Kubernetes can verify runAsNonRoot (65532 is "nonroot" in distroless).
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["/nodejs/bin/node", "src/healthcheck.js"]
CMD ["src/server.js"]
