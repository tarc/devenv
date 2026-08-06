#!/usr/bin/env bash

set -euo pipefail

# proactive-agent.HARNESS.1
# Already running inside the devenv shell; nesting another `devenv shell` here
# would discard the module input the test harness set up.
acai skill --install
