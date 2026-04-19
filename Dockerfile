# ─── Stage 1: Build with Zola ────────────────────────────────
FROM ghcr.io/getzola/zola:v0.22.1 AS builder

COPY . /project
WORKDIR /project
RUN ["zola", "build"]

# ─── Stage 2: Serve with Nginx ────────────────────────────────
FROM nginx:alpine

COPY --from=builder /project/public /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
