# k3s-multipass-install
Highly functional K3s lab for Linux or macOS via Ubuntu Multipass

## Usage
```bash
./k3s-multipass-install.sh -w <num_workers> -c <num_cpus> -m <mem_size -d <disk_size>
```

Example:
```bash
./k3s-multipass-install.sh -w 3 -c 2 -m 4096 -d 20
```

## ToDo
- Error handling