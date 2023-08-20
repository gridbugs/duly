boot:
	# Install the bootstrapping tool.
	opam install -y ./boot
	# Use the bootstrapping tool to build the main tool.
	opam exec spice_boot -- --root=.
	# Install the main tool.
	opam install -y ./_dune
	# Use the main tool to build the main tool.
	opam exec spice -- --root=.
	# Re-install the main tool after rebuilding it with itself.
	opam install -y ./_dune

clean:
	rm -rf _dune boot/_build

.PHONY: boot clean
