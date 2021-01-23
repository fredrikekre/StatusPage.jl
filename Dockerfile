FROM julia:1.6
WORKDIR /app
RUN mkdir /depot
ENV JULIA_DEPOT_PATH="/depot"
ADD *.toml /app/
RUN julia --project=/app -e "using Pkg; Pkg.instantiate()"
RUN chmod 777 -R /depot/compiled
ADD . /app
CMD ["julia", "--project=/app", "-e", "import StatusPage; StatusPage.run()"]
