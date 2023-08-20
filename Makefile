boot:
	opam install -y ./boot
	opam exec spice_boot -- --root=.
	opam install -y ./_dune
	opam exec spice -- --root=.
	opam install -y ./_dune

.PHONY: boot
