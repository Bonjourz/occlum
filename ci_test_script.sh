#/bin/bash

set -e

WORKDIR=$(cd $(dirname $0); pwd)
OCCLUM_DIR=/root/occlum
MODE=HW
OCCLUM_VERSION=0.28.0$(grep "Version =" src/pal/include/occlum_version.h |  awk '{print $4}')
CONTAINER_NAME=LOCAL_PKU_TEST

function prepare() {
    # Create container
    docker run -itd --name=$CONTAINER_NAME --privileged \
        --net host \
        -v /dev/sgx/enclave:/dev/sgx/enclave \
        -v /dev/sgx/provision:/dev/sgx/provision \
        -v $WORKDIR:/root/occlum \
        occlum/occlum:$OCCLUM_VERSION-ubuntu20.04

    # Change download source of crates.io
    docker exec $CONTAINER_NAME bash -c "cat <<- EOF >/root/.cargo/config
[source]

[source.mirror]
registry = \"https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/\"

[source.crates-io]
replace-with = \"mirror\""

    # Work around permission issue
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/grpc-rust";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/itoa-sgx";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/resolv-conf";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/ringbuf";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/rust-sgx-sdk";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/sefs";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/serde-json-sgx";
    docker exec $CONTAINER_NAME bash -c "git config --global --add safe.directory /root/occlum/deps/serde-sgx"

    # Build dependencies
    docker exec $CONTAINER_NAME bash -c "cargo uninstall sccache || true; cd /root/occlum; make submodule"
}

function rm_container() {
    docker rm -f $CONTAINER_NAME
}

# - name: C test
function c_test() {
    docker exec $CONTAINER_NAME bash -c "cd /root/occlum/demos/hello_c && make;
            occlum new occlum_instance;
            cd occlum_instance && rm -rf image;
            copy_bom -f ../hello.yaml --root image --include-dir /opt/occlum/etc/template;
            SGX_MODE=HW occlum build;
            occlum run /bin/hello_world"
}

function demo_test() {
    prepare
    c_test
    rm_container
}

prepare
exit 0

# sed -i 's/"pkru": 0/"pkru": 1/g' Occlum.json

#- name: C with encrypted image test
function c_test() {
    docker exec $CONTAINER_NAME bash -c "cd /root/occlum/demos/hello_c && make;
            occlum new occlum_instance;
            cp hello_world occlum_instance/image/bin;
            cd occlum_instance && occlum build;
            occlum run /bin/hello_world"
}

function c_with_encrypted_image_test() {
    docker exec $CONTAINER_NAME bash -c "cd /root/occlum/demos/hello_c && make;
            rm -rf occlum_instance && occlum new occlum_instance;
            occlum gen-image-key occlum_instance/image_key;
            cp hello_world occlum_instance/image/bin;
            cd occlum_instance && occlum build --image-key ./image_key --buildin-image-key;
            occlum run /bin/hello_world"
}

# - name: C++ test
function cpp_test() {
    docker exec $CONTAINER_NAME bash -c "cd /root/occlum/demos/hello_cc && make;
            occlum new occlum_instance;
            cp hello_world occlum_instance/image/bin;
            cd occlum_instance && occlum build;
            occlum run /bin/hello_world"
}

#name: Rust test
function rust_test {
    docker exec ${{ env.CONTAINER_NAME }} bash -c "cd /root/occlum/demos/rust && ./run_rust_demo_on_occlum.sh"
}

# - name: Embedded mode test
function embedded_mode_test {
    pushd $OCCLUM_DIR/demos/embedded_mode
    rm -rf occlum_instance | true
    make
    make test
    popd
}

# - name: Run Golang sqlite test
function golang_sqlite_test() {
    pushd $OCCLUM_DIR/demos/golang/go_sqlite/
    rm -rf go.mod | true
    ./run_go_sqlite_demo.sh
    popd
}

# - name: Go Server set up and run
function go_server_test() {
    pushd $OCCLUM_DIR/demos/golang/web_server 
    rm -rf go.mod | true
    occlum-go mod init web_server
    occlum-go get -u -v github.com/gin-gonic/gin
    occlum-go build -o web_server ./web_server.go;
    ./run_golang_on_occlum.sh
    popd
}

# Set up Golang grpc pingpong test
function setup_glong_grpc_pingpong() {
    export GO111MODULE=on && export GOPROXY=https://goproxy.cn;
    pushd $OCCLUM_DIR/demos/golang/grpc_pingpong
    ./prepare_ping_pong.sh
    popd
    export GO111MODULE=""
    export GOPROXY=""
}

# Start Golang grpc pingpong server
function golang_grpc_pingpong_server() {
    pushd $OCCLUM_DIR/demos/golang/grpc_pingpong
    ./run_pong_on_occlum.sh &
    popd
}

# Run Golang grpc ping test
function golang_grpc_ping_test() {
    sleep 30
    pushd $OCCLUM_DIR/demos/golang/grpc_pingpong
    ./run_ping_on_occlum.sh
    popd
}

# Run curl test
function curl_test() {
    curl http://127.0.0.1:8090/ping
}

# Run java test
function run_java_test() {
    pushd $OCCLUM_DIR/demos/java
    occlum-javac ./hello_world/Main.java
    popd

    pushd $OCCLUM_DIR/demos/java
    ./run_java_on_occlum.sh hello
    popd

    pushd $OCCLUM_DIR/demos/java
    occlum-javac ./processBuilder/processBuilder.java
    popd

    pushd $OCCLUM_DIR/demos/java
    ./run_java_on_occlum.sh processBuilder
    popd
}

# Run fish test
function fun_fish_test() {
    pushd $OCCLUM_DIR/demos/fish
    ./download_and_build.sh
    ./run_fish_test.sh
    ./run_per_process_config_test.sh
}

# Run Bazel test
function run_bazel_test() {
    pushd $OCCLUM_DIR/demos/hello_bazel
    wget https://github.com/bazelbuild/bazel/releases/download/3.2.0/bazel-3.2.0-installer-linux-x86_64.sh
    chmod +x bazel-3.2.0-installer-linux-x86_64.sh
    ./bazel-3.2.0-installer-linux-x86_64.sh

    ./build_bazel_sample.sh
    rm -rf occlum_instance | true
    occlum new occlum_instance
    cd occlum_instance
    rm -rf image
    copy_bom -f ../bazel.yaml --root image --include-dir /opt/occlum/etc/template
    occlum build
    occlum run /bin/hello-world
}

# http server test
function run_http_server_test() {
    pushd $OCCLUM_DIR/demos/https_server
    ./download_and_build_mongoose.sh
    ./run_https_server_in_occlum.sh &
    curl -k https://127.0.0.1:8443
    pkill -9 occlum | true
    popd
}

# local attestation test
function run_loccal_attestation_test() {
    pushd $OCCLUM_DIR/demos/local_attestation
    ./download_src_and_build_deps.sh
    make
    make test
    popd
}

# sqlite test
function run_sqlite_test() {
    pushd $OCCLUM_DIR/demos/sqlite
    ./download_and_build_sqlite.sh
    ./run_sqlite_on_occlum.sh
    popd
}

# xgboost_test
function run_xgboost_test() {
    pushd $OCCLUM_DIR/demos/xgboost
    ./download_and_build_xgboost.sh
    make test
    make test-local-cluster
    popd
}

# tensorflow_lite_test
function run_tensorflow_lite_test() {
    pushd $OCCLUM_DIR/demos/tensorflow_lite
    ./download_and_build_tflite.sh
    ./run_tflite_in_occlum.sh demo
    ./run_tflite_in_occlum.sh benchmark
    popd
}

# pytorch_test
function run_pytorch_test() {
    pushd $OCCLUM_DIR/demos/pytorch
    ./install_python_with_conda.sh
    ./run_pytorch_on_occlum.sh 2>&1 | tee /root/occlum/log
    sleep 360;
    cat "/root/occlum/log"
    if grep -q Done "/root/occlum/log"; then
        pkill -9 occlum | true
    else
        exit 1
    fi
    popd
}

# tensorflow_test
function run_tensorflow_test() {
    pushd $OCCLUM_DIR/demos/tensorflow/tensorflow_training

    ./install_python_with_conda.sh
    ./run_tensorflow_on_occlum.sh 2>&1 | tee /root/occlum/log
    popd
}

# bash_test
function run_bash_test() {
    pushd $OCCLUM_DIR/demos/bash
    SGX_MODE=$MODE ./run_bash_demo.sh musl
    SGX_MODE=$MODE ./run_bash_demo.sh
    popd
}

# c_test
# c_encrypt_test
# cpp_test
# rust_test
# embedded_mode_test
# golang_sqlite_test
# go_server_test
# curl_test
# setup_glong_grpc_pingpong
# golang_grpc_pingpong_server
# golang_grpc_ping_test
# run_java_test
# fun_fish_test
# run_bazel_test
# run_http_server_test
# run_sqlite_test
# run_xgboost_test
# run_tensorflow_lite_test
# run_pytorch_test
# run_tensorflow_test
run_bash_test


echo ""
echo ""
echo "Test Done"
echo ""

exit 0

    - name: Curl test
      run: |
        sleep ${{ 240 }};
        docker exec ${{ github.job }} bash -c "curl http://127.0.0.1:8090/ping"

    - name: Set up Golang grpc pingpong test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/grpc_pingpong && ./prepare_ping_pong.sh"

    - name: Start Golang grpc pingpong server
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/grpc_pingpong && SGX_MODE=SIM ./run_pong_on_occlum.sh" &

    - name: Run Golang grpc ping test
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/grpc_pingpong && SGX_MODE=SIM ./run_ping_on_occlum.sh" &

pushd /root/ngo_pku/demos/java
occlum-javac ./hello_world/Main.java
./run_java_on_occlum.sh hello
occlum-javac ./processBuilder/processBuilder.java
./run_java_on_occlum.sh processBuilder
popd

pushd /root/ngo_pku/demos/fish
./download_and_build.sh
./run_fish_test.sh
./run_per_process_config_test.sh
popd

  Bazel_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Install bazel
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/hello_bazel && wget https://github.com/bazelbuild/bazel/releases/download/3.2.0/bazel-3.2.0-installer-linux-x86_64.sh;
              chmod +x bazel-3.2.0-installer-linux-x86_64.sh;
              ./bazel-3.2.0-installer-linux-x86_64.sh"

    - name: Build bazel dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/hello_bazel && ./build_bazel_sample.sh"

    - name: Test bazel
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/hello_bazel && occlum new occlum_instance;
            cd occlum_instance && rm -rf image && copy_bom -f ../bazel.yaml --root image --include-dir /opt/occlum/etc/template;
            SGX_MODE=SIM occlum build;
            occlum run /bin/hello-world"


  Https_server_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build https server dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/https_server && ./download_and_build_mongoose.sh"

    - name: Run https server
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/https_server && SGX_MODE=SIM ./run_https_server_in_occlum.sh" &

    - name: Curl test
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "curl -k https://127.0.0.1:8443"


  Local_attestation_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build LA dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/local_attestation && ./download_src_and_build_deps.sh"

    - name: Run LA test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/local_attestation && SGX_MODE=SIM make;
              SGX_MODE=SIM make test"


  Sqlite_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build sqlite dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sqlite && ./download_and_build_sqlite.sh"

    - name: Run sqlite test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sqlite && SGX_MODE=SIM ./run_sqlite_on_occlum.sh"


  Xgboost_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build xgboost dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/xgboost && ./download_and_build_xgboost.sh"

    - name: Run xgboost test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/xgboost && SGX_MODE=SIM make test"

    - name: Run xgboost cluster test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/xgboost && SGX_MODE=SIM make test-local-cluster"


  Tensorflow_lite_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build Tensorflow-lite dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/tensorflow_lite && ./download_and_build_tflite.sh"

    - name: Run Tensorflow-lite demo
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/tensorflow_lite && SGX_MODE=SIM ./run_tflite_in_occlum.sh demo"

    - name: Run Tensorflow-lite benchmark
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/tensorflow_lite && SGX_MODE=SIM ./run_tflite_in_occlum.sh benchmark"


  Pytorch_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build python and pytorch
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/pytorch; ./install_python_with_conda.sh"

    - name: Run pytorch test
      run: docker exec -d ${{ github.job }} bash -c "cd /root/occlum/demos/pytorch; SGX_MODE=SIM ./run_pytorch_on_occlum.sh 2>&1 | tee /root/occlum/log"

    # FIXME: PyTorch can't exit normally in SIM mode
    - name: Kill the container
      run: |
        sleep 360;
        cat "$GITHUB_WORKSPACE/log";
        if grep -q Done "$GITHUB_WORKSPACE/log"; then
          docker stop ${{ github.job }}
        else
          exit 1
        fi


  Tensorflow_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build python and tensorflow
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/tensorflow/tensorflow_training; ./install_python_with_conda.sh"

    - name: Run tensorflow test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/tensorflow/tensorflow_training; SGX_MODE=SIM ./run_tensorflow_on_occlum.sh 2>&1 | tee /root/occlum/log"


# Below tests needs test image to run faster
  Grpc_musl_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - name: Create container
      run: docker run -itd --name=${{ github.job }} -v $GITHUB_WORKSPACE:/root/occlum occlumbackup/occlum:latest-ubuntu20.04-grpc

    - name: Build dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum; make submodule"

    - name: Make install
      run: docker exec ${{ github.job }} bash -c "source /opt/intel/sgxsdk/environment; cd /root/occlum; OCCLUM_RELEASE_BUILD=y make install"

    - name: Prepare grpc sample project
      run: docker exec ${{ github.job }} bash -c "cd /root/demos/grpc/grpc_musl && ./prepare_client_server.sh"

    - name: Run grpc server
      run: docker exec ${{ github.job }} bash -c "cd /root/demos/grpc/grpc_musl && SGX_MODE=SIM ./run_server_on_occlum.sh" &

    - name: Run grpc client
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "cd /root/demos/grpc/grpc_musl && SGX_MODE=SIM ./run_client_on_occlum.sh"

  Grpc_tls_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build openssl and grpc
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_tls;
            ./download_and_install_openssl.sh && ./download_and_install_grpc.sh"

    - name: Prepare grpc tls occlum instance
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_tls;
            SGX_MODE=SIM ./prepare_occlum_instance.sh"

    - name: Run grpc tls server
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_tls/occlum_server;
            occlum run /bin/greeter_secure_server" &

    - name: Run grpc tls client
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_tls/occlum_client;
            occlum run /bin/greeter_secure_client"

  Grpc_glibc_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download and Install grpc
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && ./download_and_install_grpc_glibc.sh"

    - name: Prepare grpc sample project
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && ./prepare_client_server_glibc.sh"

    - name: Run grpc server
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && SGX_MODE=SIM ./run_server_on_occlum_glibc.sh" &

    - name: Run grpc client
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && SGX_MODE=SIM ./run_client_on_occlum_glibc.sh"

    - name: Prepare grpc stress test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && ./prepare_stress_test_tool.sh"

    - name: Run grpc stress client
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/grpc/grpc_glibc && SGX_MODE=SIM ./run_stress_test.sh"

  Openvino_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - name: Create container
      run: docker run -itd --name=${{ github.job }} -v $GITHUB_WORKSPACE:/root/occlum occlumbackup/occlum:latest-ubuntu20.04-openvino

    - name: Build dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum; make submodule"

    - name: Make install
      run: docker exec ${{ github.job }} bash -c "source /opt/intel/sgxsdk/environment; cd /root/occlum; OCCLUM_RELEASE_BUILD=y make install"

    - name: Run openVINO benchmark
      run: docker exec ${{ github.job }} bash -c "cd /root/demos/openvino && cp -rf /root/occlum/demos/openvino/* . && SGX_MODE=SIM ./run_benchmark_on_occlum.sh"


  # Python test also needs its own image because in Alpine environment, modules are built locally and consumes a lot of time.
  Python_musl_support_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true
    - name: Create container
      run: docker run -itd --name=${{ github.job }} -v $GITHUB_WORKSPACE:/root/occlum occlumbackup/occlum:latest-ubuntu20.04-python

    - name: Build dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum; make submodule"

    - name: Make install
      run: docker exec ${{ github.job }} bash -c "source /opt/intel/sgxsdk/environment; cd /root/occlum; OCCLUM_RELEASE_BUILD=1 make install"

    - name: Run python support test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/python_musl; SGX_MODE=SIM ./run_python_on_occlum.sh"

    - name: Check result
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/python_musl/occlum_instance; cat smvlight.dat"

  # Python glibc support test
  Python_glibc_support_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: download conda and build python
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/python_glibc; ./install_python_with_conda.sh"

    - name: Run python glibc support test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/python_glibc; SGX_MODE=SIM ./run_python_on_occlum.sh"

    - name: Check result
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/python_glibc/occlum_instance; cat smvlight.dat"

  # Redis test
  Redis_support_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: download and build redis
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/redis; ./download_and_build_redis.sh"

    - name: Run redis benchmark
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/redis; SGX_MODE=SIM ./benchmark.sh"

    - name: Restart the container
      run: |
        sleep ${{ env.nap_time }};
        docker restart ${{ github.job }}

    - name: download and build redis with glibc
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/redis; ./download_and_build_redis_glibc.sh"

    - name: Run redis benchmark
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/redis; SGX_MODE=SIM ./benchmark_glibc.sh"

  flink_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download flink
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/flink && ./download_flink.sh"

    - name: Run jobmanager on host
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/flink && SGX_MODE=SIM ./run_flink_jobmanager_on_host.sh"

    - name: Run flink taskmanager
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/flink && SGX_MODE=SIM ./run_flink_on_occlum_glibc.sh tm"

    - name: Run flink task
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/flink && SGX_MODE=SIM ./run_flink_on_occlum_glibc.sh task"

    - name: Check flink task manager's log
      if: ${{ always() }}
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/flink; cat occlum_instance_taskmanager/flink--taskmanager-0.log"

  Cluster_serving_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Set up environment
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/cluster_serving; source ./environment.sh; ./install-dependencies.sh"

    - name: Run cluster serving test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/cluster_serving; source ./environment.sh; SGX_MODE=SIM ./start-all.sh && ./push-image.sh"

    - name: Check flink task manager's log
      if: ${{ always() }}
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/cluster_serving; cat flink/flink--taskmanager-0.log"

  enclave_ra_tls_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download and build Enclave TLS
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/enclave_tls && ./download_and_build_enclave_tls.sh"

    - name: Run the encalve tls server on Occlum
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/enclave_tls && SGX_MODE=SIM ./run_enclave_tls_server_in_occlum.sh"

    # Ignore the result here as simulation mode doesn't have RA capabilities
    - name: Run the encalve tls client
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "/usr/share/enclave-tls/samples/enclave-tls-client" || true

  vault_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download and build HashiCorp Vault
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/vault && ./prepare_vault.sh"

    - name: Run the Vault server on Occlum
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/vault && SGX_MODE=SIM ./run_occlum_vault_server.sh"

    - name: Run the Vault client
      run: |
        sleep 360;
        docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/vault && ./run_occlum_vault_test.sh"

    - name: Check Vault log
      if: ${{ always() }}
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/golang/vault && sync && cat vault.log"

  sofaboot_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Install Maven
      run: docker exec ${{ github.job }} bash -c "apt update && apt install -y maven"

    - name: Download and compile sofaboot web demos
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sofaboot && ./download_compile_sofaboot.sh"

    - name: Run SOFABoot web demo
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sofaboot && SGX_MODE=SIM ./run_sofaboot_on_occlum.sh"

    - name: Check SOFABoot result
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "curl -s http://localhost:8080/actuator/readiness | grep -v DOWN"
        
    - name: Check SOFABoot log
      if: ${{ always() }}
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sofaboot && sync && cat sofaboot.log"

  Bash_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Run musl-libc Bash test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/bash && SGX_MODE=SIM ./run_bash_demo.sh musl"

    - name: Run glibc Bash test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/bash && SGX_MODE=SIM ./run_bash_demo.sh"

  Sysbench_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Run sysbench download and build
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sysbench && SGX_MODE=SIM ./dl_and_build.sh"

    - name: Run prepare sysbench occlum instance
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sysbench && SGX_MODE=SIM ./prepare_sysbench.sh"

    - name: Run sysbench threads benchmark
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/sysbench/occlum_instance;
            occlum run /bin/sysbench threads --threads=200 --thread-yields=100 --thread-locks=4 --time=30 run"

  FIO_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Build fio dependencies
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/fio && ./download_and_build_fio.sh"

    - name: Run fio test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/fio && SGX_MODE=SIM ./run_fio_on_occlum.sh fio-seq-read.fio"

  Cross_world_unix_socket_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Run unix socket test
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/cross_world_uds; SGX_MODE=SIM ./run_cross_world_uds_test.sh"

  Gvisor_syscalls_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - name: Create container
      run: |
        docker pull occlumbackup/occlum:latest-ubuntu20.04-gvisor_test
        gvisor_test=$(docker run -itd -v $GITHUB_WORKSPACE:/root/occlum occlumbackup/occlum:latest-ubuntu20.04-gvisor_test);
        echo "gvisor_test=$gvisor_test" >> $GITHUB_ENV

    - name: Build dependencies
      run: docker exec $gvisor_test bash -c "cd /root/occlum; make submodule"

    - name: Make install
      run: docker exec $gvisor_test bash -c "source /opt/intel/sgxsdk/environment; cd /root/occlum; OCCLUM_RELEASE_BUILD=y make install"

    - name: clone code
      run: docker exec $gvisor_test bash -c "git clone https://github.com/occlum/gvisor.git"

    - name: Run gvisor syscall test
      run: docker exec $gvisor_test bash -c "cd /root/gvisor/occlum && SGX_MODE=SIM ./run_occlum_passed_tests.sh ngo"

  Flask_tls_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download conda and build python
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/flask; ./install_python_with_conda.sh"

    - name: Generate sample cert/key
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/flask; ./gen-cert.sh"

    - name: Prepare and start Flask Occlum instance
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/flask;
            SGX_MODE=SIM ./build_occlum_instance.sh; ./run_flask_on_occlum.sh &"

    - name: Test PUT
      run: |
        sleep ${{ env.nap_time }};
        docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/flask;
            curl --cacert flask.crt -X PUT https://localhost:4996/customer/1 -d "data=Tom""
    - name: Test Get
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/python/flask;
            curl --cacert flask.crt -X GET https://localhost:4996/customer/1"

  Linux_LTP_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download and build Linux LTP
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/linux-ltp && ./dl_and_build_ltp.sh"

    - name: Prepare occlum instance for LTP demo
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/linux-ltp && SGX_MODE=SIM ./prepare_ltp.sh"

    - name: Run the LTP demo
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/linux-ltp/ltp_instance;
            occlum run /opt/ltp/run-ltp.sh -f syscalls-occlum"

  Rocksdb_test:
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v1
      with:
        submodules: true

    - uses: ./.github/workflows/composite_action/sim
      with:
        container-name: ${{ github.job }}
        build-envs: 'OCCLUM_RELEASE_BUILD=1'

    - name: Download and build Rocksdb
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/rocksdb && ./dl_and_build_rocksdb.sh"

    - name: Prepare occlum instance and Run benchmark of Rocksdb
      run: docker exec ${{ github.job }} bash -c "cd /root/occlum/demos/rocksdb && SGX_MODE=SIM ./run_benchmark.sh"