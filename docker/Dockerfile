# TPC-DS on MariaDB — reproducible benchmark container
#
# Builds dsdgen from the TPC-DS sources, generates data, initialises MariaDB
# at a chosen innodb_page_size, loads, indexes and benchmarks it.
#
# The host project is mounted read-only at /project; everything the container
# writes goes to /data (scratch) and /results (bind-mounted back to the host),
# so a run never modifies the repository.

# Matches the macOS host the published results were measured on
# (13.0.2-MariaDB-log for osx10.21 on arm64, Homebrew), so a container run
# differs from the host in operating system only, not in server version.
ARG MARIADB_TAG=13.0.2
FROM mariadb:${MARIADB_TAG}

# dsdgen needs a C toolchain, yacc and lex.  procps/iproute2 are for the
# diagnostics the entrypoint prints; python3 runs the benchmark harness.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc make flex bison \
        python3 python3-venv \
        procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The TPC-DS makefile ships with OS unset; the entrypoint builds with
# OS=LINUX.  Nothing is compiled at image build time because the sources
# live in the mounted project, not in the image.

RUN mkdir -p /data /results /scratch && chown -R mysql:mysql /data /results /scratch

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY bench.py      /usr/local/bin/bench.py
RUN chmod +x /usr/local/bin/entrypoint.sh

# Only PROFILE is defaulted here.  The others are deliberately left unset so
# the profile in entrypoint.sh can choose them; an ENV default would win over
# the profile (`: "${VAR:=...}"` only assigns when unset) and silently ignore
# the profile's settings.  Override any of SCALE, PAGE_SIZE, BUFFER_POOL,
# SAMPLE_PAGES, QUERYSET or TUNED with -e at run time.
ENV PROFILE=quick

WORKDIR /project
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
