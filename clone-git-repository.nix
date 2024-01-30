# MIT License
#
# Copyright (c) 2023 ona-li-toki-e-jan-Epiphany-tawa-mi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# A library module to clone git repositories into specified folder paths.
#
# In practice, this will be idempotent, as the folders will not be deleted or
# updated.

{ lib, pkgs, config, ... }:

with lib;

let cfg = config.git;
in
{
  # Options to select which repositories to clone.
  options.git.clonedRepositories = with types; mkOption {
    default     = {};
    description = "A set of repositories to clone.";

    type = attrsOf (submodule {
      options = {
        enable = mkOption {
          default     = true;
          description = "Whether the repository should be cloned.";
          type        = bool;
        };
        url = mkOption {
          description = "The URL of the repository to clone.";
          type        = str;
        };
        target = mkOption {
          description = "The folder path to copy the repository files into.";
          type        = str;
        };
      };
    });
  };



  # Converts the repos to cloning scripts and hands them off to Home Manager to
  # run.
  config.home.activation =
    # Converts a repository defined in options to a bit of shell script that
    # will clone it to the desired location.
    concatMapAttrs (name: {target, url, ...}:
      let # This path prefix is neccesary for git and it's dependencies to be
          # accessible by the script.
          pathCommandPrefix = with pkgs; "PATH=\"${git}/bin:${openssh}/bin:$PATH\"";
      in {
        "git.clonedRepositories-${name}" = hm.dag.entryAfter ["installPackages"] ''
          if [ ! -d "${target}" ]; then
            ${pathCommandPrefix} $DRY_RUN_CMD  git clone "${url}" "${target}"
          fi
        '';
      }
    # Filters out disabled repositories.
    ) (filterAttrs (name: {enable, ...}: enable) cfg.clonedRepositories);
}
