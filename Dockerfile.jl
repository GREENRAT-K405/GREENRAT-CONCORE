FROM julia:1.9
RUN julia -e 'using Pkg; Pkg.add("JSON")'
COPY . /src 
WORKDIR /src
# mkconcore.py will append the CMD dynamically