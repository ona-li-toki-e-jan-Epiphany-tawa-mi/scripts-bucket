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

# Simple and easy-to-use containerized Tor bridge module.
# If you want to run a non-exit relay, instead all you need to do is change
# services.tor.relay.role in the container.
# It shouldn't take too much work to adapt this to be an exit relay, if you're
# going for that.

{ lib, config, ports, ... }:

let cfg = config.services.torBridge;

    # Where to put the files for Tor on the host and in the container.
    torHostDirectory      = "/mnt/tor-bridge";
    torContainerDirectory = "/var/lib/tor";
in
{
  options.services.torBridge = with lib; with types; {
    orPort = mkOption {
      description = "The OR port to use for Tor.";
      type        = port;
    };

    orPortFlags = mkOption {
      default     = [];
      description = "Flags for the OR port. See ORPort in the man tor for details.";
      type        = listOf str;
    };

    controlPort = mkOption {
      description = "The control port for the Tor daemon to use..";
      type        = port;
    };

    bandwidthRate = mkOption {
      description = "Average maximum bandwidth for Tor. See BandwitdthRate in the man tor for details.";
      type        = str;
    };

    bandwidthBurst = mkOption {
      description = "Absolute maximum bandwidth for Tor. See BandwitdthBurst in the man tor for details.";
      type        = str;
    };

    contactInfo = mkOption {
      description = "The contact info to set for this relay. See this link for more details: https://2019.www.torproject.org/docs/tor-manual.html.en#ContactInfo";
      type        = str;
    };
  };



  config = {
    # Lets bridge through firewall.
    networking.firewall.allowedTCPPorts = [ cfg.orPort ];

    # Creates persistent directory for Tor if it doesn't already exist.
    system.activationScripts."activateTorBridge" = ''
      mkdir -m 700 -p ${torHostDirectory}
    '';

    # Isolated container for the bridge
    containers."tor-bridge" = {
      ephemeral = true;
      autoStart = true;

      # Mounts persistent directory.
      bindMounts."${torContainerDirectory}" = {
        hostPath   = torHostDirectory;
        isReadOnly = false;
      };

      config = { pkgs, ... }: {
        # Sets permissions for bind mount.
        systemd.tmpfiles.rules = [ "d ${torContainerDirectory} 700 tor tor" ];

        environment.systemPackages = [ pkgs.nyx ];

        services.tor = {
          enable       = true;
          openFirewall = true;

          relay = {
            enable = true;
            role   = "bridge";
          };

          settings = {
            "ContactInfo"   = cfg.contactInfo;
            # Where people connect in from.
            "ORPort"        = [{
              port  = cfg.orPort;
              flags = cfg.orPortFlags;
            }];
            # Enables hardware acceleration.
            "HardwareAccel" = 1;
            # Sets up control port for tor to access with nyx.
            "ControlPort"   = cfg.controlPort;
            # Where to store state information.
            "DataDirectory" = torContainerDirectory;
            # Sets bandwidth limits.
            "BandwidthRate"  = cfg.bandwidthRate;
            "BandwidthBurst" = cfg.bandwidthBurst;
          };
        };

        system.stateVersion = "23.11";
      };
    };
  };
}
