# DELIBERATELY VULNERABLE image, used only by gates.yml. It is never pushed.
# An end-of-life Alpine release pinned by digest, so it stays vulnerable: its packages have
# CRITICAL fixes it will never get. gates.yml builds it through build.yml, the same
# workflow releases use, and checks that the Trivy gate blocks it before any push.
FROM alpine:3.10@sha256:451eee8bedcb2f029756dc3e9d73bab0e7943c1ac55cff3a4861c52a0fdd3e98
USER 65532:65532
CMD ["true"]
