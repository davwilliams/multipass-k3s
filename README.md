# k3s-multipass-install

Highly functional K3s lab for Linux or macOS via Ubuntu Multipass

## Usage

```bash
./k3s-multipass-install.sh -w <num_agents> -c <num_cpus> -m <mem_size -d <disk_size>
```

Example:

```bash
./k3s-multipass-install.sh -w 3 -c 2 -m 4096 -d 20
```

## ToDo

- Add support for multiple K3s server nodes
- Add support for MSSQL and dqlite cluster DB backend (via Kine)
- Add support for advanced configuration of K3s server and agent nodes
- Error handling