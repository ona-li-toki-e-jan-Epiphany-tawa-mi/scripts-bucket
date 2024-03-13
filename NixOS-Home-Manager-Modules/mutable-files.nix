# MIT License
#
# Copyright (c) 2024 ona-li-toki-e-jan-Epiphany-tawa-mi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# A library module that allows writing out configuration files even when
# programs choose to overwrite those files and destroy the symlinks.

{ lib, config, ... }:

with lib;

let cfg = config.mutable;
in
{
  options.mutable.file = mkOption {
    default     = {};
    description = ''
      Writes out a file to the specified location, overwriting the file if it already
      exists.

      This is used instead of home.file when the program in question overwrites the
      symlink. This breaks the system and will prevent rebuilding until the file is
      removed.

      Either mutable.file."<file>".source or mutable.file."<file>".text must be set.
    '';

    type = with types; attrsOf (submodule {
      options = {
        enable = mkOption {
          default     = true;
          description = "Whether the file should be generated.";
          type        = bool;
        };

        source = mkOption {
          default     = null;
          description = "Path to the file to get text to write from. Mutally exclusive with mutable.file.<file>.text.";
          type        = nullOr path;
        };

        target = mkOption {
          default     = null;
          defaultText = "name";                   # Will be set to name later if left null.
          description = "The folder path relative to HOME to write the file to.";
          type        = nullOr str;
        };

        text = mkOption {
          default     = null;
          description = "The text to write. Mutally exclusive with mutable.file.<file>.text.";
          type        = nullOr str;
        };
      };
    });
  };



  # Note: I would use lib.trivial.pipe here but it seems to be borked? It kept
  # returning a function.
  config.home.activation =
    let # Checks to see if there is at least one file that is enabled.
        existsEnabledFile = foldlAttrs (accumulator: name: {enable, ...}: accumulator || enable) false cfg.file;
    in mkIf existsEnabledFile (
      # Generates scripts to overwrite the target files.
      concatMapAttrs (name: value:
        let target = if value.target != null then value.target else name;
            text   = if value.text != null then value.text else readFromFile value.source;
        in {
          # The deleter script is used to delete the original files before the
          # "symlink" is generated.
          "mutable.files-${name}-deleter" = hm.dag.entryBefore ["checkLinkTargets"] ''
            $DRY_RUN_CMD rm --recursive --force "${target}"
          '';

          # The linker script is used to write out the specified file as a
          # "symlink."
          "mutable.files-${name}-linker" = hm.dag.entryAfter ["linkGeneration"] ''
            $DRY_RUN_CMD mkdir  --parents "$(dirname ${target})"
            $DRY_RUN_CMD cat > "${target}" << EOF
            ${text}
            EOF
          '';
        }
      # Filters out disabled files.
      ) (filterAttrs (name: {enable, ...}: enable) cfg.file)
    );
}
