FROM ghcr.io/ecohealthalliance/repel-base

EXPOSE 8000

COPY plumber.R /
COPY .env /

ENTRYPOINT ["R", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8000)"]
