# ─── Build static site with Zola ────────────────────────────────
FROM ghcr.io/getzola/zola:v0.22.1

COPY . /project
WORKDIR /project

CMD ["zola", "build"]
