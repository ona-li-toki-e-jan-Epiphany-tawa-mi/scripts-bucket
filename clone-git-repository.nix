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
