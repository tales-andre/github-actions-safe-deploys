# DELIBERATELY BROKEN release, used only by scripts/gate-broken-release.sh.
# It is the good image with one change: the start command points at a file that does not
# exist, so every pod exits at start and never becomes ready.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
CMD ["src/does-not-exist.js"]
