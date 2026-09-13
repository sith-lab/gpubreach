#!/bin/sh

echo "-------------------------------------------"
echo ""
echo "###########################################"
echo "[INFO] 1. Build Executables and Install Dependencies"
echo "###########################################"

python3 -m pip install matplotlib torch==2.10.0 torchvision==0.25.0

cd $HAMMER_ROOT/src
rm -rf out
cmake -S . -B out/build
cd out/build && make -j 
cd $BREACH_ROOT

cd src/
rm -rf out
cmake -S . -B out
cd out && make -j

cd $BREACH_ROOT

if [ ! -e "$BREACH_ROOT/data_scripts/cupqc_exploit/cupqc-sdk-0.4.0-x86_64" ]; then
    cd $BREACH_ROOT/data_scripts/cupqc_exploit
    wget https://developer.nvidia.com/downloads/compute/cupqc/downloads/secure/cupqc-sdk-0.4.0-x86_64.tar.gz
    tar -xvzf cupqc-sdk-0.4.0-x86_64.tar.gz
    rm cupqc-sdk-0.4.0-x86_64.tar.gz
    cd $BREACH_ROOT
fi

if [ ! -e "$BREACH_ROOT/ILSVRC2012_img_val.tar" ]; then
    echo "Error: Did not find ImageNet Validation Set. Please follow the README to download."
    exit 1
else
    cd $BREACH_ROOT/data_scripts/ml_exploit 
    rm -rf val
    mkdir val
    tar -xvf $BREACH_ROOT/ILSVRC2012_img_val.tar -C ./val
    python3 ./filter_validation_set.py ./val ./rand_val_labels.txt
    cd $BREACH_ROOT
fi

echo "-------------------------------------------"
echo ""
echo "###########################################"
echo "[INFO] 3. Running Artifacts"
echo "###########################################"

bash run_fig5.sh
bash run_fig7.sh
bash run_fig8.sh
bash run_fig10.sh
bash run_t2.sh
bash run_gpubreach_demo.sh
bash run_cupqc_exploit.sh
bash run_ml_exploit.sh
