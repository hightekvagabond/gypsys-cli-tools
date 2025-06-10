# Netdata – Build & Install from Source

:contentReference[oaicite:1]{index=1}

---

## 🚀 Why Build from Source?

- :contentReference[oaicite:2]{index=2}
- :contentReference[oaicite:3]{index=3}
- :contentReference[oaicite:4]{index=4}

---

## 🔗 Step 1: Clone the Repo

```bash
git clone https://github.com/netdata/netdata.git
cd netdata
git submodule update --init --recursive
````

This ensures all dependencies, including plugins and core components, are fetched. ([learn.netdata.cloud][1])

---

## 🛠️ Step 2: Build & Install

Using **Ninja (recommended)**:

```bash
mkdir build && cd build
cmake -S .. -B . -G Ninja
cmake --build .
sudo cmake --install .
```

Or using **Make**:

```bash
mkdir build && cd build
cmake -S .. -B .
cmake --build .
sudo cmake --install .
```

To see build-time options:

```bash
cmake -LH ..
```

You can enable plugins or disable ACLK (Cloud component) here. ([learn.netdata.cloud][1], [community.netdata.cloud][2])

---

## 🧬 Step 3: eBPF Kernel Collector (Optional)

For advanced metrics (network, VFS, process activity):

1. Check `packaging/ebpf.version` in your repo.
2. Download the matching `netdata-kernel-collector-*.tar.xz` from GitHub releases.
3. Extract and copy `.o` and `.so.*` files into `/usr/libexec/netdata/plugins.d/` or your Netdata plugin folder. ([learn.netdata.cloud][1])

---

## 🕵️‍♂️ Step 4: Run & Enable

```bash
sudo systemctl enable --now netdata
systemctl status netdata
```

Then visit:

```
http://localhost:19999
```

---

## 🔌 Step 5: Integrate & Configure

* Main config: `/etc/netdata/netdata.conf`
* Plugins: `/etc/netdata/go.d/` and `/etc/netdata/health.d/`
* Alerting and thresholds: see `/etc/netdata/health_alarm_notify.conf`

After tweaking:

```bash
sudo systemctl restart netdata
```

---

## 🧹 Step 6: Clean & Rebuild

Update from Git:

```bash
git pull
git submodule update --init --recursive
cd build
cmake --build . --clean-first
sudo cmake --install .
```

---

## ⚙️ Integrate with `gypsys-cli-tools`

Suggested `Makefile` targets:

```makefile
netdata-build:
	git clone ... || cd netdata && git pull
	cd netdata && git submodule update --init --recursive
	mkdir -p netdata/build && cd netdata/build
	cmake -S .. -B . -G Ninja
	cmake --build . --parallel
	sudo cmake --install .

netdata-enable:
	sudo systemctl enable --now netdata

netdata-clean:
	cd netdata/build && cmake --build . --clean-first
```

---

## ✅ At a Glance

| Method       | Use Case                       | Benefits                            |
| ------------ | ------------------------------ | ----------------------------------- |
| Kickstart    | Quick install / updates        | One-liner, nightly builds           |
| GitHub build | Custom setup / dev environment | Control, customization, latest code |

---

## 📚 References

* GitHub instructions on `git submodule` and Ninja/Make builds ([github.com][3], [learn.netdata.cloud][1])
* eBPF collector download & install steps ([learn.netdata.cloud][1])

