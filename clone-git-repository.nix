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
        mapAttrs' (name: {target, url, ...}:
          {
            name  = "git.clonedRepositories-${name}";
            value = hm.dag.entryAfter ["installPackages"] ''
              if [ ! -d "${target}" ]; then
                ${pathCommandPrefix} $DRY_RUN_CMD git clone "${url}" "${target}"
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
            Unit = {
              Description = serviceDescription;
              After       = [ "network-online.target" ];
            };

            # Generates a script to run git pull on the relavent repositories.
            Service.ExecStart = pkgs.writeShellScript "auto-pull-repositories.sh" (
              foldlAttrs (accumulator: name: {target, ...}: accumulator + ''
                ${pathCommandPrefix} $DRY_RUN_CMD git -C "${target}" pull
              '') "" (filterAttrs (name: {enable, autoPull, ...}: enable && autoPull) cfg.clonedRepositories)
            );
          };

          # Runs the autoPullRepositories service once a week.
          timers."${serviceName}" = {
            Unit.Description = serviceDescription;
            Timer            = {
              OnCalendar = "weekly";
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
    };
}
