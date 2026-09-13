sudo nvidia-smi -i 0 -pm 1
sudo nvidia-smi -lgc=$1,$1
sudo nvidia-smi -lmc=$2,$2
sudo nvidia-smi -i 0 -pm 1