{
  description = "Development environment for ChampSim BNN Predictor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    champsim-src = {
      url = "github:ChampSim/ChampSim";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, champsim-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          torch
          numpy
          pip
        ]);

        # A derivation that builds ChampSim with the BNN predictor
        champsim-bnn = pkgs.stdenv.mkDerivation {
          pname = "champsim-bnn";
          version = "3.0.3"; 
          src = champsim-src;

          nativeBuildInputs = [ pkgs.cmake pkgs.gnumake pkgs.pkg-config pythonEnv ];
          buildInputs = with pkgs; [ xz zlib bzip2 boost nlohmann_json gtest fmt range-v3 cli11 ];

          configurePhase = ''
            # Inject the local predictors from the repository into ChampSim's source
            mkdir -p branch/hybrid_bnn_gshare
            cp ${./cc_predictors/hybrid_bnn_common.h} branch/hybrid_bnn_gshare/hybrid_bnn_common.h
            cp ${./cc_predictors/hybrid_bnn_gshare/hybrid_bnn_gshare.cc} branch/hybrid_bnn_gshare/hybrid_bnn_gshare.cc
            cp ${./cc_predictors/hybrid_bnn_gshare/hybrid_bnn_gshare.h} branch/hybrid_bnn_gshare/hybrid_bnn_gshare.h

            mkdir -p branch/hybrid_bnn_2bit
            cp ${./cc_predictors/hybrid_bnn_common.h} branch/hybrid_bnn_2bit/hybrid_bnn_common.h
            cp ${./cc_predictors/hybrid_bnn_2bit/hybrid_bnn_2bit.cc} branch/hybrid_bnn_2bit/hybrid_bnn_2bit.cc
            cp ${./cc_predictors/hybrid_bnn_2bit/hybrid_bnn_2bit.h} branch/hybrid_bnn_2bit/hybrid_bnn_2bit.h

            # Generate config.json
            cat > bnn_config.json <<EOF
            {
                "executable_name": "champsim",
                "block_size": 64,
                "page_size": 4096,
                "heartbeat_frequency": 10000000,
                "num_cores": 1,
                "branch_predictor": "hybrid_bnn_gshare",
                "btb": "basic_btb",
                "i-cache": {
                    "sets": 64, "ways": 8, "pq_size": 32, "mshr_size": 8, "latency": 4,
                    "max_tag_check": 2, "max_fill": 2, "prefetcher": "next_line"
                },
                "d-cache": {
                    "sets": 64, "ways": 8, "pq_size": 32, "mshr_size": 16, "latency": 4,
                    "max_tag_check": 2, "max_fill": 2, "prefetcher": "next_line"
                },
                "l2c": {
                    "sets": 512, "ways": 8, "pq_size": 32, "mshr_size": 32, "latency": 10,
                    "max_tag_check": 2, "max_fill": 2, "prefetcher": "next_line"
                },
                "llc": {
                    "sets": 2048, "ways": 16, "pq_size": 32, "mshr_size": 64, "latency": 20,
                    "max_tag_check": 2, "max_fill": 2, "prefetcher": "next_line"
                },
                "physical_memory": {
                    "channels": 1, "ranks": 1, "banks": 8, "rows": 65536, "columns": 128,
                    "lines_per_column": 1, "channel_width": 8, "bus_freq": 1600,
                    "tRP": 12.5, "tRCD": 12.5, "tCAS": 12.5, "latency": 50
                },
                "virtual_memory": {
                    "ptw_mshr_size": 16, "ptw_max_tag_check": 2, "ptw_max_fill": 2, "ptw_latency": 1
                }
            }
            EOF

            # Explicitly export paths for the compiler
            # Create a dummy CLI11 library because ChampSim erroneously tries to link against it
            # even though it is header-only in Nixpkgs.
            mkdir -p fake_lib
            ar rcs fake_lib/libCLI11.a

            export CXXFLAGS="-I.csconfig"
            export LDFLAGS="-L$(pwd)/fake_lib"

            python3 config.sh bnn_config.json
          '';

          buildPhase = ''
            make
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp bin/champsim $out/bin/champsim
          '';
        };
      in
      {
        packages.default = champsim-bnn;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gcc
            gnumake
            cmake
            binutils
            pkg-config
            xz
            zlib
            bzip2
            nlohmann_json
            boost
            gtest
            fmt
            range-v3
            cli11
            pythonEnv
            git
            champsim-bnn
          ];

          shellHook = ''
            echo "--- ChampSim BNN Development Shell (Flake) ---"
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib:${pkgs.xz}/lib:${pkgs.bzip2}/lib:${pkgs.fmt}/lib:$LD_LIBRARY_PATH"
            
            if [ ! -d ".venv" ]; then
              echo "Creating virtual environment in .venv..."
              python -m venv .venv --system-site-packages
            fi
            
            source .venv/bin/activate
            
            if ! python -c "import torchbnn" &>/dev/null; then
              echo "torchbnn not found. Installing now..."
              pip install torchbnn
            fi

            echo ""
            echo "Commands available:"
            echo "  champsim - Run the pre-built ChampSim with BNN (Gshare default)"
            echo ""
          '';
        };
      }
    );
}
