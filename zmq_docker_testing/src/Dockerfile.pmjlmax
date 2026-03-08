FROM julia:1.12
COPY . /src 
WORKDIR /src/Concore
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'
WORKDIR /src
# mkconcore.py will append the CMD dynamically
CMD ["julia", "--project=Concore", "-i", "pmjlmax.jl"]
