# EnvyOS

EnvyOS is a distro of mesh-related utilities (firmware, host tools, clients). It builds on open-source projects and adds a cohesive UX. Current stack is MeshCore-based:

* MeshCore
* Bootlaoder
* Peaky Finders
* envybot
* mcmt-gateway
* Client apps

EnvyOS adds these enhancements:

* Improved message routing
* Simplified UI in client apps
* mOTA (Mesh Over the Air) updates
* Bug fixes in advance of upstream 

## Peaky Finders

RF planner. Pin is **0.5.0**. Extract `peaky-0.5.0-<target>.tar.gz` from the EnvyOS (or [Peaky](https://github.com/MeshEnvy/peaky-finders/releases)) GitHub Release, then:

```bash
./peaky serve /path/to/project --port 8080
```

Open `http://127.0.0.1:8080/`. An empty directory gets a starter `config.yaml`.

From this repo (`./envyos build peaky` stages the binaries). Apple Silicon example:

```bash
./envyos build peaky
./build/main/bench/peaky-v0.5.0/peaky-0.5.0-aarch64-apple-darwin/peaky \
  serve /path/to/project --port 8080
```

Linux x64 uses `peaky-0.5.0-x86_64-unknown-linux-gnu`. Copy `peaky` onto your `PATH` if you want. Full usage: [MeshEnvy/peaky-finders](https://github.com/MeshEnvy/peaky-finders#run).

See [`docs/package-maintainer-guide.md`](docs/package-maintainer-guide.md) to implement a package harness or bundle an existing package into the distro.

All projects are licenced and distributed under their original licenses. Code written independently is licensed under MIT.