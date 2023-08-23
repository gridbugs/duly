bootstrap:
	# Make sure dune is installed
	opam install -y dune
	# Generate a naive dune version of spice with a shell script.
	scripts/generate_dune_bootstrap_project .
	# Install the naive spice package with opam.
	opam install -y _spice/dune_generated/spice.opam
	# Use the newly-installed naive spice package to rebuild spice.
	opam exec spice -- --root=.
	# Installed the bootstrapped version of spice.
	opam install -y _spice/dune_generated/spice.opam
	# As a sanity-check re-build spice with the bootstrapped spice.
	opam exec spice -- --root=.
	# Installed the rebuilt version of spice.
	opam install -y _spice/dune_generated/spice.opam

clean:
	rm -rf _spice/dune_generated

mrproper:
	rm -rf _opam _spice .merlin

.PHONY: bootstrap clean mrproper
