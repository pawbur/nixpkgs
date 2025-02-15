{ lib, stdenv
, fetchurl, perl, gcc
, ncurses5
, ncurses6, gmp, libiconv, numactl
, llvmPackages

  # minimal = true; will remove files that aren't strictly necessary for
  # regular builds and GHC bootstrapping.
  # This is "useful" for staying within hydra's output limits for at least the
  # aarch64-linux architecture.
, minimal ? false
}:

# Prebuilt only does native
assert stdenv.targetPlatform == stdenv.hostPlatform;

let
  downloadsUrl = "https://downloads.haskell.org/ghc";

  version = "8.10.5";

  # Information about available bindists that we use in the build.
  #
  # # Bindist library checking
  #
  # The field `archSpecificLibraries` also provides a way for us get notified
  # early when the upstream bindist changes its dependencies (e.g. because a
  # newer Debian version is used that uses a new `ncurses` version).
  #
  # Usage:
  #
  # * You can find the `fileToCheckFor` of libraries by running `readelf -d`
  #   on the compiler binary (`exePathForLibraryCheck`).
  # * To skip library checking for an architecture,
  #   set `exePathForLibraryCheck = null`.
  # * To skip file checking for a specific arch specfic library,
  #   set `fileToCheckFor = null`.
  ghcBinDists = {
    # Binary distributions for the default libc (e.g. glibc, or libSystem on Darwin)
    # nixpkgs uses for the respective system.
    defaultLibc = {
      i686-linux = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-i386-deb9-linux.tar.xz";
          sha256 = "17cwmhhyz952psmp4j3pkdj0yrfxah3l2dawg5s4hdr228n5pjqc";
        };
        exePathForLibraryCheck = "ghc/stage2/build/tmp/ghc-stage2";
        archSpecificLibraries = [
          # The i686-linux bindist provided by GHC HQ is currently built on Debian 9,
          # which link it against `libtinfo.so.5` (ncurses 5).
          # Other bindists are linked `libtinfo.so.6` (ncurses 6).
          { nixPackage = ncurses5; fileToCheckFor = "libtinfo.so.5"; }
        ];
      };
      x86_64-linux = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-x86_64-deb10-linux.tar.xz";
          sha256 = "11v76wgljyszc6mgz6r16i6wkifgl15a26q7ablihp2cr8h3qqmw";
        };
        exePathForLibraryCheck = "ghc/stage2/build/tmp/ghc-stage2";
        archSpecificLibraries = [
          { nixPackage = ncurses6; fileToCheckFor = "libtinfo.so.6"; }
        ];
      };
      armv7l-linux = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-armv7-deb10-linux.tar.xz";
          sha256 = "0v5bvhb2z9j26yr0n9gc4xdq2lm37mr98g62p5z8pqahhhd0s5sn";
        };
        exePathForLibraryCheck = "ghc/stage2/build/tmp/ghc-stage2";
        archSpecificLibraries = [
          { nixPackage = ncurses6; fileToCheckFor = "libtinfo.so.6"; }
        ];
      };
      aarch64-linux = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-aarch64-deb10-linux.tar.xz";
          sha256 = "1p0dgyn1m2nd8ax1g25lchaz9z2nk9jvyzf63biarq7qlzc5q24s";
        };
        exePathForLibraryCheck = "ghc/stage2/build/tmp/ghc-stage2";
        archSpecificLibraries = [
          { nixPackage = ncurses6; fileToCheckFor = "libtinfo.so.6"; }
          { nixPackage = numactl; fileToCheckFor = null; }
        ];
      };
      x86_64-darwin = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-x86_64-apple-darwin.tar.xz";
          sha256 = "08javwfqd21kglbr1bnhnbjw2cggz1n668vi8kx5hbcnz3plf3zg";
        };
        exePathForLibraryCheck = null; # we don't have a library check for darwin yet
        archSpecificLibraries = [
          { nixPackage = ncurses6; fileToCheckFor = null; }
          { nixPackage = libiconv; fileToCheckFor = null; }
        ];
      };
      aarch64-darwin = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-aarch64-apple-darwin.tar.xz";
          sha256 = "02fbcrzcc6m25z3ji867isml38jkg4blry70ljwl3l03zxq4ws03";
        };
        exePathForLibraryCheck = null; # we don't have a library check for darwin yet
        archSpecificLibraries = [
          { nixPackage = ncurses6; fileToCheckFor = null; }
          { nixPackage = libiconv; fileToCheckFor = null; }
        ];
      };
    };
    # Binary distributions for the musl libc for the respective system.
    musl = {
      x86_64-linux = {
        src = {
          url = "${downloadsUrl}/${version}/ghc-${version}-x86_64-alpine3.10-linux-integer-simple.tar.xz";
          sha256 = "1ql2qxywbbv0b9syvrm9kyh5d8midnl676lw4698ajras6gcvmzl";
        };
        exePathForLibraryCheck = "bin/ghc";
        archSpecificLibraries = [
          # In contrast to glibc builds, the musl-bindist uses `libncursesw.so.*`
          # instead of `libtinfo.so.*.`
          { nixPackage = ncurses6; fileToCheckFor = "libncursesw.so.6"; }
        ];
      };
    };
  };

  distSetName = if stdenv.hostPlatform.isMusl then "musl" else "defaultLibc";

  binDistUsed = ghcBinDists.${distSetName}.${stdenv.hostPlatform.system}
    or (throw "cannot bootstrap GHC on this platform ('${stdenv.hostPlatform.system}' with libc '${distSetName}')");

  useLLVM = !stdenv.targetPlatform.isx86;

  libPath =
    lib.makeLibraryPath (
      [
        gmp
      ]
      # Add arch-specific libraries.
      ++ map ({ nixPackage, ... }: nixPackage) binDistUsed.archSpecificLibraries
    );

  libEnvVar = lib.optionalString stdenv.hostPlatform.isDarwin "DY"
    + "LD_LIBRARY_PATH";

in

stdenv.mkDerivation rec {
  inherit version;

  name = "ghc-${version}-binary";

  src = fetchurl binDistUsed.src;

  nativeBuildInputs = [ perl ];
  propagatedBuildInputs =
    lib.optionals useLLVM [ llvmPackages.llvm ]
    # Because musl bindists currently provide no way to tell where
    # libgmp is (see not [musl bindists have no .buildinfo]), we need
    # to propagate `gmp`, otherwise programs built by this ghc will
    # fail linking with `cannot find -lgmp` errors.
    # Also, as of writing, the release pages of musl bindists claim
    # that they use `integer-simple` and do not require `gmp`; however
    # that is incorrect, so `gmp` is required until a release has been
    # made that includes https://gitlab.haskell.org/ghc/ghc/-/issues/20059.
    # (Note that for packaging the `-binary` compiler, nixpkgs does not care
    # about whether or not `gmp` is used; this comment is just here to explain
    # why the `gmp` dependency exists despite what the release page says.)
    ++ lib.optionals stdenv.hostPlatform.isMusl [ gmp ]; # musl bindist needs this

  # Set LD_LIBRARY_PATH or equivalent so that the programs running as part
  # of the bindist installer can find the libraries they expect.
  # Cannot patchelf beforehand due to relative RPATHs that anticipate
  # the final install location.
  ${libEnvVar} = libPath;

  postUnpack =
    # Verify our assumptions of which `libtinfo.so` (ncurses) version is used,
    # so that we know when ghc bindists upgrade that and we need to update the
    # version used in `libPath`.
    lib.optionalString
      (binDistUsed.exePathForLibraryCheck != null)
      # Note the `*` glob because some GHCs have a suffix when unpacked, e.g.
      # the musl bindist has dir `ghc-VERSION-x86_64-unknown-linux/`.
      # As a result, don't shell-quote this glob when splicing the string.
      (let buildExeGlob = ''ghc-${version}*/"${binDistUsed.exePathForLibraryCheck}"''; in
        lib.concatStringsSep "\n" [
          (''
            echo "Checking that ghc binary exists in bindist at ${buildExeGlob}"
            if ! test -e ${buildExeGlob}; then
              echo >&2 "GHC binary ${binDistUsed.exePathForLibraryCheck} could not be found in the bindist build directory (at ${buildExeGlob}) for arch ${stdenv.hostPlatform.system}, please check that ghcBinDists correctly reflect the bindist dependencies!"; exit 1;
            fi
          '')
          (lib.concatMapStringsSep
            "\n"
            ({ fileToCheckFor, nixPackage }:
              lib.optionalString (fileToCheckFor != null) ''
                echo "Checking bindist for ${fileToCheckFor} to ensure that is still used"
                if ! readelf -d ${buildExeGlob} | grep "${fileToCheckFor}"; then
                  echo >&2 "File ${fileToCheckFor} could not be found in ${binDistUsed.exePathForLibraryCheck} for arch ${stdenv.hostPlatform.system}, please check that ghcBinDists correctly reflect the bindist dependencies!"; exit 1;
                fi

                echo "Checking that the nix package ${nixPackage} contains ${fileToCheckFor}"
                if ! test -e "${lib.getLib nixPackage}/lib/${fileToCheckFor}"; then
                  echo >&2 "Nix package ${nixPackage} did not contain ${fileToCheckFor} for arch ${stdenv.hostPlatform.system}, please check that ghcBinDists correctly reflect the bindist dependencies!"; exit 1;
                fi
              ''
            )
            binDistUsed.archSpecificLibraries
          )
        ])
    # GHC has dtrace probes, which causes ld to try to open /usr/lib/libdtrace.dylib
    # during linking
    + lib.optionalString stdenv.isDarwin ''
      export NIX_LDFLAGS+=" -no_dtrace_dof"
      # not enough room in the object files for the full path to libiconv :(
      for exe in $(find . -type f -executable); do
        isScript $exe && continue
        ln -fs ${libiconv}/lib/libiconv.dylib $(dirname $exe)/libiconv.dylib
        install_name_tool -change /usr/lib/libiconv.2.dylib @executable_path/libiconv.dylib -change /usr/local/lib/gcc/6/libgcc_s.1.dylib ${gcc.cc.lib}/lib/libgcc_s.1.dylib $exe
      done
    '' +

    # Some scripts used during the build need to have their shebangs patched
    ''
      patchShebangs ghc-${version}/utils/
      patchShebangs ghc-${version}/configure
    '' +
    # We have to patch the GMP paths for the integer-gmp package.
    # Note [musl bindists have no .buildinfo]
    # Note that musl bindists do not contain them; unclear if that's intended;
    # see: https://gitlab.haskell.org/ghc/ghc/-/issues/20073#note_363231
    ''
      find . -name integer-gmp.buildinfo \
          -exec sed -i "s@extra-lib-dirs: @extra-lib-dirs: ${gmp.out}/lib@" {} \;
    '' + lib.optionalString stdenv.isDarwin ''
      find . -name base.buildinfo \
          -exec sed -i "s@extra-lib-dirs: @extra-lib-dirs: ${libiconv}/lib@" {} \;
    '' +
    # aarch64 does HAVE_NUMA so -lnuma requires it in library-dirs in rts/package.conf.in
    # FFI_LIB_DIR is a good indication of places it must be needed.
    lib.optionalString (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) ''
      find . -name package.conf.in \
          -exec sed -i "s@FFI_LIB_DIR@FFI_LIB_DIR ${numactl.out}/lib@g" {} \;
    '' +
    # Rename needed libraries and binaries, fix interpreter
    lib.optionalString stdenv.isLinux ''
      find . -type f -executable -exec patchelf \
          --interpreter ${stdenv.cc.bintools.dynamicLinker} {} \;
    '';

  # fix for `configure: error: Your linker is affected by binutils #16177`
  preConfigure = lib.optionalString
    stdenv.targetPlatform.isAarch32
    "LD=ld.gold";

  configurePlatforms = [ ];
  configureFlags = [
    "--with-gmp-includes=${lib.getDev gmp}/include"
    # Note `--with-gmp-libraries` does nothing for GHC bindists:
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/6124
  ] ++ lib.optional stdenv.isDarwin "--with-gcc=${./gcc-clang-wrapper.sh}"
    # From: https://github.com/NixOS/nixpkgs/pull/43369/commits
    ++ lib.optional stdenv.hostPlatform.isMusl "--disable-ld-override";

  # No building is necessary, but calling make without flags ironically
  # calls install-strip ...
  dontBuild = true;

  # Apparently necessary for the ghc Alpine (musl) bindist:
  # When we strip, and then run the
  #     patchelf --set-rpath "${libPath}:$(patchelf --print-rpath $p)" $p
  # below, running ghc (e.g. during `installCheckPhase)` gives some apparently
  # corrupted rpath or whatever makes the loader work on nonsensical strings:
  #     running install tests
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: : symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: ir6zf6c9f86pfx8sr30n2vjy-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/../lib/x86_64-linux-ghc-8.10.5/libHSexceptions-0.10.4-ghc8.10.5.so: symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: y/lib/ghc-8.10.5/bin/../lib/x86_64-linux-ghc-8.10.5/libHStemplate-haskell-2.16.0.0-ghc8.10.5.so: symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: 8.10.5/libHStemplate-haskell-2.16.0.0-ghc8.10.5.so: symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: �: symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: �?: symbol not found
  #     Error relocating /nix/store/...-ghc-8.10.2-binary/lib/ghc-8.10.5/bin/ghc: 64-linux-ghc-8.10.5/libHSexceptions-0.10.4-ghc8.10.5.so: symbol not found
  # This is extremely bogus and should be investigated.
  dontStrip = if stdenv.hostPlatform.isMusl then true else false; # `if` for explicitness

  # On Linux, use patchelf to modify the executables so that they can
  # find editline/gmp.
  postFixup = lib.optionalString stdenv.isLinux
    (if stdenv.hostPlatform.isAarch64 then
      # Keep rpath as small as possible on aarch64 for patchelf#244.  All Elfs
      # are 2 directories deep from $out/lib, so pooling symlinks there makes
      # a short rpath.
      ''
      (cd $out/lib; ln -s ${ncurses6.out}/lib/libtinfo.so.6)
      (cd $out/lib; ln -s ${gmp.out}/lib/libgmp.so.10)
      (cd $out/lib; ln -s ${numactl.out}/lib/libnuma.so.1)
      for p in $(find "$out/lib" -type f -name "*\.so*"); do
        (cd $out/lib; ln -s $p)
      done

      for p in $(find "$out/lib" -type f -executable); do
        if isELF "$p"; then
          echo "Patchelfing $p"
          patchelf --set-rpath "\$ORIGIN:\$ORIGIN/../.." $p
        fi
      done
      ''
    else
      ''
      for p in $(find "$out" -type f -executable); do
        if isELF "$p"; then
          echo "Patchelfing $p"
          patchelf --set-rpath "${libPath}:$(patchelf --print-rpath $p)" $p
        fi
      done
    '') + lib.optionalString stdenv.isDarwin ''
    # not enough room in the object files for the full path to libiconv :(
    for exe in $(find "$out" -type f -executable); do
      isScript $exe && continue
      ln -fs ${libiconv}/lib/libiconv.dylib $(dirname $exe)/libiconv.dylib
      install_name_tool -change /usr/lib/libiconv.2.dylib @executable_path/libiconv.dylib -change /usr/local/lib/gcc/6/libgcc_s.1.dylib ${gcc.cc.lib}/lib/libgcc_s.1.dylib $exe
    done

    for file in $(find "$out" -name setup-config); do
      substituteInPlace $file --replace /usr/bin/ranlib "$(type -P ranlib)"
    done
  '' +
  lib.optionalString minimal ''
    # Remove profiling files
    find $out -type f -name '*.p_o' -delete
    find $out -type f -name '*.p_hi' -delete
    find $out -type f -name '*_p.a' -delete
    # `-f` because e.g. musl bindist does not have this file.
    rm -f $out/lib/ghc-*/bin/ghc-iserv-prof
    # Hydra will redistribute this derivation, so we have to keep the docs for
    # legal reasons (retaining the legal notices etc)
    # As a last resort we could unpack the docs separately and symlink them in.
    # They're in $out/share/{doc,man}.
  '';

  # In nixpkgs, musl based builds currently enable `pie` hardening by default
  # (see `defaultHardeningFlags` in `make-derivation.nix`).
  # But GHC cannot currently produce outputs that are ready for `-pie` linking.
  # Thus, disable `pie` hardening, otherwise `recompile with -fPIE` errors appear.
  # See:
  # * https://github.com/NixOS/nixpkgs/issues/129247
  # * https://gitlab.haskell.org/ghc/ghc/-/issues/19580
  hardeningDisable = lib.optional stdenv.targetPlatform.isMusl "pie";

  doInstallCheck = true;
  installCheckPhase = ''
    unset ${libEnvVar}
    # Sanity check, can ghc create executables?
    cd $TMP
    mkdir test-ghc; cd test-ghc
    cat > main.hs << EOF
      {-# LANGUAGE TemplateHaskell #-}
      module Main where
      main = putStrLn \$([|"yes"|])
    EOF
    $out/bin/ghc --make main.hs || exit 1
    echo compilation ok
    [ $(./main) == "yes" ]
  '';

  passthru = {
    targetPrefix = "";
    enableShared = true;

    # Our Cabal compiler name
    haskellCompilerName = "ghc-${version}";
  };

  meta = rec {
    homepage = "http://haskell.org/ghc";
    description = "The Glasgow Haskell Compiler";
    license = lib.licenses.bsd3;
    # HACK: since we can't encode the libc / abi in platforms, we need
    # to make the platform list dependent on the evaluation platform
    # in order to avoid eval errors with musl which supports less
    # platforms than the default libcs (i. e. glibc / libSystem).
    # This is done for the benefit of Hydra, so `packagePlatforms`
    # won't return any platforms that would cause an evaluation
    # failure for `pkgsMusl.haskell.compiler.ghc8102Binary`, as
    # long as the evaluator runs on a platform that supports
    # `pkgsMusl`.
    platforms = builtins.attrNames ghcBinDists.${distSetName};
    hydraPlatforms = builtins.filter (p: minimal || p != "aarch64-linux") platforms;
    maintainers = with lib.maintainers; [ lostnet ];
  };
}
