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

# A library module to clone git repositories into specified folder paths, and,
# optionally run git pull on them periodically.

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
        autoPull = mkOption {
          default     = false;
          description = "Whether to automatically run git pull on the repository every week.";
          type        = bool;
        };
        remotes = mkOption {
          description = "A mapping between the names and URLs of the remotes to add. The remote name 'origin' to clone the repository.";
          type        = attrsOf str;
        };
        target = mkOption {
          description = "The folder path to copy the repository files into.";
          type        = str;
        };
      };
    });
  };



  config =
    let # Checks to see if there is at least one repository that is enabled.
        existsEnabledRepository = foldlAttrs (accumulator: name: {enable, ...}: accumulator || enable) false cfg.clonedRepositories;
        # This path prefix is neccesary for git and it's dependencies to be
        # accessible by the script.
        pathCommandPrefix = with pkgs; "PATH=\"${git}/bin:${openssh}/bin:$PATH\"";
    in mkIf existsEnabledRepository {
      # Converts the repos to cloning scripts and hands them off to Home Manager
      # to run.
      home.activation =
        # Converts a repository defined in options to a bit of shell script that
        # will clone it to the desired location.
        mapAttrs' (name: {target, remotes, ...}:
          {
            name  = "git.clonedRepositories-${name}";
            value = hm.dag.entryAfter ["installPackages"] ''
              if [ ! -d "${target}" ]; then
                ${pathCommandPrefix} $DRY_RUN_CMD git clone "${remotes."origin"}" "${target}"

                # Adds remotes for the other URLs.
                ${lib.concatStrings (mapAttrsToList (name: url:
                  if name != "origin"
                  then ''
                    ${pathCommandPrefix} $DRY_RUN_CMD git -C "${target}" remote add "${name}" "${url}"
                  ''
                  else ""
                ) remotes)}
              fi
            '';
          }
        # Filters out disabled repositories.
        ) (filterAttrs (name: {enable, ...}: enable) cfg.clonedRepositories);

      # Runs a user service every week to run git pull on the repositories that
      # have autoPull set.
      systemd.user =
        let # Checks to see if there is at least one repository that is enabled and needs to be automatically pulled.
            existsAutoPuller   = foldlAttrs (accumulator: name: {enable, autoPull, ...}: accumulator || (enable && autoPull)) false cfg.clonedRepositories;
            serviceName        = "autoPullRepositories";
            serviceDescription = "Automatically run git pull on select repositories.";
        in mkIf existsAutoPuller {
          # User service to run git pull.
          services."${serviceName}" = {
            "Unit" = {
              "Description" = serviceDescription;
              "After"       = [ "network-online.target" ];
            };

            "Service" = {
              "Type" = "oneshot";
              # Generates a script to run git pull on the relavent repositories.
              "ExecStart" = pkgs.writeShellScript "auto-pull-repositories.sh" (
                foldlAttrs (accumulator: name: {target, ...}: accumulator + ''
                  ${pathCommandPrefix} $DRY_RUN_CMD git -C "${target}" pull
                '') "" (filterAttrs (name: {enable, autoPull, ...}: enable && autoPull) cfg.clonedRepositories)
              );
            };
          };

          # Runs the autoPullRepositories service once a week.
          timers."${serviceName}" = {
            "Unit"."Description" = serviceDescription;
            "Timer"              = {
              "OnCalendar" = "weekly";
              "Persistent" = true;
            };
            "Install"."WantedBy" = [ "timers.target" ];
          };
        };
    };
}
