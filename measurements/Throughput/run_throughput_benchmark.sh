#!/bin/bash
# run_throughput_benchmark.sh
# Runs both Python and Julia ZMQ throughput tests one after another

cd "$(dirname "$0")"

# Allow Python to find concore.py which is two directories up (in the root)
export PYTHONPATH="c:/GSOC/GREENRAT-CONCORE/"

echo "======================================"
echo "    Python ZMQ Throughput Benchmark   "
echo "======================================"
echo "Starting Python Server in background..."
python funbody_throughput_test.py &
PY_SERVER_PID=$!
sleep 2

echo "Starting Python Client..."
python funcall_throughput_test.py

echo "Killing Python Server..."
kill $PY_SERVER_PID
sleep 1

echo ""
echo "======================================"
echo "    Julia ZMQ Throughput Benchmark    "
echo "======================================"
echo "Starting Julia Server in background..."
# Force Julia to load Concore from the local lib/julia/Concore directory
julia --project=../../lib/julia/Concore funbody_throughput_test.jl &
JL_SERVER_PID=$!
sleep 10 # Wait a bit longer for Julia JIT to compile and start

echo "Starting Julia Client..."
julia --project=../../lib/julia/Concore funcall_throughput_test.jl

echo "Killing Julia Server..."
kill $JL_SERVER_PID
wait $PY_SERVER_PID 2>/dev/null
wait $JL_SERVER_PID 2>/dev/null

echo ""
echo "Benchmark finished! Compare the 'Throughput: X messages/sec' lines above."
