if [ ! -d "./my_work_dir" ]; then
    mkdir ./my_work_dir
fi

python3 ../include/RV64IMD_assembler.py

xrun -work WORK -access +r -sv ../test/dual_testbench.sv -l ./my_work_dir/xrun.log -xmlibdirpath ./my_work_dir +define+DEBUG_EN > ./my_work_dir/run.log

if grep -q "xmvlog: .*W" ./my_work_dir/run.log; then
    echo "WARNING detected:"
    grep "xmvlog: .*W" ./my_work_dir/run.log
fi

if grep -q "xmelab: *W" ./my_work_dir/run.log; then
    echo "WARNING detected:"
    grep "xmelab: *W" ./my_work_dir/run.log
fi

if grep -q "xmvlog: .*E" ./my_work_dir/run.log; then
    echo "ERROR detected:"
    grep "xmvlog: .*E" ./my_work_dir/run.log
    exit 1
fi

mv dump.vcd ./my_work_dir